package store_test

import (
 "bytes"
 "encoding/json"
 "errors"
 "fmt"
 "os"
 "os/exec"
 "path/filepath"
 "sync"
 "testing"
 "time"

 bolt "go.etcd.io/bbolt"
 "github.com/Rynaro/eidolons/gauge/internal/contract"
 "github.com/Rynaro/eidolons/gauge/internal/store"
)

func seeded(t *testing.T) string {
 t.Helper();path:=filepath.Join(t.TempDir(),"state.db");if e:=store.Create(path,"controller-instance");e!=nil{t.Fatal(e)}
 db,e:=store.Open(path,time.Second);if e!=nil{t.Fatal(e)};defer db.Close()
 for _,id:=range []string{"root-a","root-b"}{r:=contract.Root{ID:id,Phase:"staged",Generation:"generation-"+id,Inventory:"inventory-"+id};if e=db.Stage(r,nil);e!=nil{t.Fatal(e)};if e=db.Activate(id,r.Generation,r.Inventory);e!=nil{t.Fatal(e)}}
 return path
}

func read(t *testing.T,path string) store.Snapshot {t.Helper();s,e:=store.Inspect(path,time.Second);if e!=nil{t.Fatal(e)};return s}

func TestV406T03(t *testing.T) {
 for _,fault:=range []string{"future","migration","partial","corrupt"}{t.Run(fault,func(t *testing.T){
  path:=seeded(t)
  if fault=="corrupt"{if e:=os.WriteFile(path,[]byte("not a bolt database"),0600);e!=nil{t.Fatal(e)}}else{
   db,e:=bolt.Open(path,0600,nil);if e!=nil{t.Fatal(e)}
   e=db.Update(func(tx *bolt.Tx)error{switch fault{case "future":return tx.Bucket([]byte("meta")).Put([]byte("schema"),[]byte("999"));case "migration":return tx.Bucket([]byte("meta")).Put([]byte("schema"),[]byte("0"));default:return tx.DeleteBucket([]byte("history"))}});if e!=nil{t.Fatal(e)};db.Close()
  }
  before,_:=os.ReadFile(path)
  if _,e:=store.Inspect(path,100*time.Millisecond);e==nil{t.Fatal("bad state inspected as valid")}
  if d,e:=store.Open(path,100*time.Millisecond);e==nil{d.Close();t.Fatal("bad state opened writable")}
  after,_:=os.ReadFile(path);if !bytes.Equal(before,after){t.Fatal("refusal mutated database")}
 })}
 t.Run("missing",func(t *testing.T){p:=filepath.Join(t.TempDir(),"absent.db");if _,e:=store.Inspect(p,time.Second);e==nil{t.Fatal("missing accepted")};if _,e:=os.Stat(p);!os.IsNotExist(e){t.Fatal("read created database")}})
 t.Run("mutation guard",func(t *testing.T){path:=seeded(t);db,e:=store.Open(path,time.Second);if e!=nil{t.Fatal(e)};defer db.Close();
  // Fault injection uses the backend directly; application mutation must still guard.
  if e=db.BackendForTest().Update(func(tx *bolt.Tx)error{return tx.Bucket([]byte("meta")).Put([]byte("schema"),[]byte("999"))});e!=nil{t.Fatal(e)}
  if e=db.Update("root-a","generation-root-a",func(tx *store.Tx)error{return tx.Put(contract.Record{ID:"bad",Family:"knowledge",Kind:"note",Body:json.RawMessage(`{}`)})});e==nil{t.Fatal("mutation skipped schema guard")}
 })
}

func putPair(tx *store.Tx,key string) error {
 for _,p:=range [][2]string{{"history","receipt"},{"policy","policy"}}{if e:=tx.Put(contract.Record{ID:key,Family:p[0],Kind:p[1],Body:json.RawMessage(`{"value":1}`)});e!=nil{return e}}
 return nil
}

func TestV406T05(t *testing.T) {
 path:=seeded(t);db,e:=store.Open(path,time.Second);if e!=nil{t.Fatal(e)}
 sentinel:=errors.New("callback rollback")
 if e=db.Update("root-a","generation-root-a",func(tx *store.Tx)error{if e:=putPair(tx,"rolled-back");e!=nil{return e};return sentinel});!errors.Is(e,sentinel){t.Fatal(e)}
 db.Close();if len(read(t,path).Records["root-a"])!=0{t.Fatal("partial callback commit")}
 const count=12;start:=make(chan struct{});var wg sync.WaitGroup;errs:=make(chan error,count)
 for i:=0;i<count;i++{wg.Add(1);go func(i int){defer wg.Done();<-start;d,e:=store.Open(path,10*time.Second);if e!=nil{errs<-e;return};defer d.Close();errs<-d.Update("root-a","generation-root-a",func(tx *store.Tx)error{return putPair(tx,fmt.Sprint(i))})}(i)}
 close(start);wg.Wait();close(errs);for e:=range errs{if e!=nil{t.Fatal(e)}}
 snap:=read(t,path);if len(snap.Records["root-a"])!=2*count || len(snap.Records["root-b"])!=0{t.Fatal("lost records or cross-root leak")}
 db,e=store.Open(path,time.Second);if e!=nil{t.Fatal(e)}
 started:=time.Now();if d,e:=store.Open(path,80*time.Millisecond);e==nil{d.Close();t.Fatal("simultaneous writer")};if time.Since(started)>time.Second{t.Fatal("unbounded lock")};db.Close()
 db,e=store.Open(path,time.Second);if e!=nil{t.Fatal("lock did not release",e)}
 mutate:=func(payload string)error{return db.Update("root-a","generation-root-a",func(tx *store.Tx)error{fresh,e:=tx.Once("retry",[]byte(payload));if e!=nil||!fresh{return e};return putPair(tx,"retry")})}
 if e=mutate("same");e!=nil{t.Fatal(e)};if e=mutate("same");e!=nil{t.Fatal(e)};if e=mutate("conflict");e==nil{t.Fatal("identity conflict accepted")};db.Close()
 if len(read(t,path).Records["root-a"])!=2*count+2{t.Fatal("retry duplicated dependent records")}
 if string(snap.Records["root-a"][0].Body)!="{\"value\":1}"{t.Fatal("returned bytes outlived transaction incorrectly")}
 t.Log("sync enabled; local Linux/macOS process-interruption boundary; no power-loss/network-filesystem claim")
}

func TestV406T05_Process(t *testing.T) {
 for _,phase:=range []string{"before","after"}{t.Run(phase,func(t *testing.T){
  path:=seeded(t);barrier:=filepath.Join(t.TempDir(),"barrier")
  cmd:=exec.Command(os.Args[0],"-test.run=^TestStoreProcessHelper$");cmd.Env=append(os.Environ(),"GAUGE_CHILD_DB="+path,"GAUGE_CHILD_PHASE="+phase,"GAUGE_CHILD_BARRIER="+barrier)
  if e:=cmd.Start();e!=nil{t.Fatal(e)};defer func(){_ = cmd.Process.Kill();_ = cmd.Wait()}()
  deadline:=time.Now().Add(15*time.Second);for{if _,e:=os.Stat(barrier);e==nil{break};if time.Now().After(deadline){t.Fatal("child did not reach real commit barrier")};time.Sleep(10*time.Millisecond)}
  if e:=cmd.Process.Kill();e!=nil{t.Fatal(e)};_ = cmd.Wait()
  s:=read(t,path);want:=0;if phase=="after"{want=2};if len(s.Records["root-a"])!=want{t.Fatalf("interruption %s exposed partial/lost commit: %d",phase,len(s.Records["root-a"]))}
  d,e:=store.Open(path,time.Second);if e!=nil{t.Fatal(e)};for i:=0;i<2;i++{if e=d.Update("root-a","generation-root-a",func(tx *store.Tx)error{fresh,e:=tx.Once("killed-operation",[]byte("payload"));if e!=nil||!fresh{return e};return putPair(tx,"killed")});e!=nil{t.Fatal(e)}};d.Close()
  if len(read(t,path).Records["root-a"])!=2{t.Fatal("retry was not exactly once")}
 })}
}

func TestStoreProcessHelper(t *testing.T) {
 path:=os.Getenv("GAUGE_CHILD_DB");if path==""{return};phase:=os.Getenv("GAUGE_CHILD_PHASE");barrier:=os.Getenv("GAUGE_CHILD_BARRIER")
 block:=func(){if e:=os.WriteFile(barrier,[]byte(phase),0600);e!=nil{t.Fatal(e)};select{}}
 d,e:=store.Open(path,time.Second);if e!=nil{t.Fatal(e)};defer d.Close()
 e=d.Update("root-a","generation-root-a",func(tx *store.Tx)error{fresh,e:=tx.Once("killed-operation",[]byte("payload"));if e!=nil||!fresh{return e};if e=putPair(tx,"killed");e!=nil{return e};if phase=="before"{block()};return nil});if e!=nil{t.Fatal(e)};block()
}

func TestV406T07_Persistence(t *testing.T){
 path:=seeded(t);d,e:=store.Open(path,time.Second);if e!=nil{t.Fatal(e)}
 e=d.Update("root-a","generation-root-a",func(tx *store.Tx)error{for _,p:=range [][2]string{{"history","receipt"},{"context","context-reference"},{"knowledge","note"},{"policy","policy"}}{if e:=tx.Put(contract.Record{ID:p[0],Family:p[0],Kind:p[1],Body:json.RawMessage(`{"ref":"kept"}`)});e!=nil{return e}};return nil});if e!=nil{t.Fatal(e)}
 if e=d.Update("root-a","generation-root-a",func(tx *store.Tx)error{return tx.Put(contract.Record{ID:"bad",Family:"policy",Kind:"note",Body:json.RawMessage(`{}`)})});e==nil{t.Fatal("note elevated into policy")};d.Close()
 if len(read(t,path).Records["root-a"])!=4{t.Fatal("state families not persisted")}
}
