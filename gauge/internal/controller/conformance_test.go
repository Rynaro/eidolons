package controller_test

import (
 "bytes"
 "context"
 "encoding/json"
 "errors"
 "fmt"
 "os"
 "os/exec"
 "path/filepath"
 "reflect"
 "strings"
 "sync"
 "sync/atomic"
 "testing"
 "time"

 "github.com/Rynaro/eidolons/gauge/internal/contract"
 "github.com/Rynaro/eidolons/gauge/internal/controller"
 "github.com/Rynaro/eidolons/gauge/internal/store"
)

func repo(t *testing.T)string{t.Helper();p:=os.Getenv("GAUGE_REPO");if p==""{t.Fatal("GAUGE_REPO missing")};return p}
func cli(t *testing.T, project string,args ...string)([]byte,[]byte,int){t.Helper();c:=exec.Command("bash",append([]string{filepath.Join(repo(t),"cli/eidolons")},args...)...);c.Dir=project;c.Env=append(os.Environ(),"EIDOLONS_HOME="+filepath.Join(project,"home"),"EIDOLONS_NEXUS="+repo(t),"EIDOLONS_LEDGER_LOCK_TIMEOUT=1");var out,err bytes.Buffer;c.Stdout=&out;c.Stderr=&err;e:=c.Run();rc:=0;if e!=nil{var ee *exec.ExitError;if !errors.As(e,&ee){t.Fatal(e)};rc=ee.ExitCode()};return out.Bytes(),err.Bytes(),rc}
func service(t *testing.T, p string)*controller.Service{t.Helper();return controller.New(p,controller.Options{Timeout:time.Second})}
func readStore(t *testing.T,p string)store.Snapshot{t.Helper();s,e:=store.Inspect(filepath.Join(p,".eidolons/.ledger/.gauge-controller-v1/state.db"),time.Second);if e!=nil{t.Fatal(e)};return s}

func TestV406T02(t *testing.T){
 p:=t.TempDir();_,err,rc:=cli(t,p,"ledger","record","--run-id","ordinary","--type","probe","--event-id","one");if rc!=0{t.Fatalf("ordinary writer: %s",err)}
 out,err,rc:=cli(t,p,"ledger","record","--run-id","ordinary","--type","probe","--event-id","one");if rc!=0||len(out)!=0||len(err)!=0{t.Fatalf("ordinary retry behavior changed: %d %q %q",rc,out,err)}
 _,err,rc=cli(t,p,"ledger","record","--run-id","ordinary","--type","different","--event-id","one");if rc==0||!strings.Contains(string(err),"event identity conflict"){t.Fatal("opt-out conflict changed")}
 if _,e:=os.Stat(filepath.Join(p,".eidolons/.ledger/.gauge-controller-v1"));!os.IsNotExist(e){t.Fatal("ordinary command initialized Gauge")}
 t.Setenv("EIDOLONS_GAUGE_BIN",filepath.Join(p,"missing"));_,err,rc=cli(t,p,"gauge","status");if rc==0||!strings.Contains(strings.ToLower(string(err)),"binary"){t.Fatalf("missing binary must be actionable: %d %s",rc,err)}
 fake:=filepath.Join(p,"explicit-bin");if e:=os.WriteFile(fake,[]byte("#!/bin/sh\nprintf '%s\\n' \"$@\"\nexit 7\n"),0700);e!=nil{t.Fatal(e)};t.Setenv("EIDOLONS_GAUGE_BIN",fake)
 out,err,rc=cli(t,p,"gauge","status","--root","ordinary");if rc!=7||string(out)!="status\n--root\nordinary\n"||len(err)!=0{t.Fatalf("explicit binary dispatch: %d %q %q",rc,out,err)}
 // The real packaged binary must work without invoking a runtime Go toolchain.
 bin:=filepath.Join(p,"gauge");build:=exec.Command("go","build","-mod=readonly","-trimpath","-buildvcs=false","-o",bin,"../../cmd/eidolons-gauge");if output,e:=build.CombinedOutput();e!=nil{t.Fatalf("binary build: %v %s",e,output)}
 t.Setenv("EIDOLONS_GAUGE_BIN",bin);_,err,rc=cli(t,p,"gauge","init","--root","new-root");if rc!=0{t.Fatalf("binary init: %s",err)}
 out,err,rc=cli(t,p,"gauge","status","--root","new-root");if rc!=0||!strings.Contains(string(out),"current_acceptance")||!strings.Contains(string(out),"unavailable"){t.Fatalf("binary status: %d %s %s",rc,out,err)}
}

func legacyFixture(t *testing.T,p,name string)string{
 t.Helper();data,e:=os.ReadFile(filepath.Join(repo(t),"cli/tests/fixtures/journal/"+name+".json"));if e!=nil{t.Fatal(e)};var events []json.RawMessage;if e=json.Unmarshal(data,&events);e!=nil{t.Fatal(e)}
 var first struct{RunID string `json:"run_id"`};_ = json.Unmarshal(events[0],&first);dir:=filepath.Join(p,".eidolons/.ledger",first.RunID,"events");if e=os.MkdirAll(dir,0700);e!=nil{t.Fatal(e)}
 for i,raw:=range events{if e=os.WriteFile(filepath.Join(dir,fmt.Sprintf("%d.json",i+1)),append(raw,'\n'),0600);e!=nil{t.Fatal(e)}}
 return first.RunID
}

func TestV406T04(t *testing.T){
 for _,fixture:=range []string{"legacy","legacy-complex"}{t.Run(fixture,func(t *testing.T){
  p:=t.TempDir();run:=legacyFixture(t,p,fixture);s:=service(t,p);if e:=s.Init();e!=nil{t.Fatal(e)}
  originals:=[][]byte{};for i:=1;i<=2;i++{raw,_:=os.ReadFile(filepath.Join(p,".eidolons/.ledger",run,"events",fmt.Sprintf("%d.json",i)));originals=append(originals,raw)}
  if e:=s.Import(run);e!=nil{t.Fatal(e)};before:=readStore(t,p);if e:=s.Import(run);e!=nil{t.Fatal("repeat import",e)};if !reflect.DeepEqual(before,readStore(t,p)){t.Fatal("repeat import mutated typed state")}
  if before.Roots[run].Phase!="staged"{t.Fatal("import silently promoted")}
  for i,event:=range before.Legacy[run]{if !bytes.Equal(event.Raw,originals[i])||event.Grade!="self-attested"||event.ID==""{t.Fatal("import rewrote bytes/identity/grade")}}
  if len(before.Legacy[run])!=2{t.Fatal("partial import")}
  if e:=s.Promote(run);e!=nil{t.Fatal(e)}
  _,err,rc:=cli(t,p,"ledger","record","--run-id",run,"--type","forbidden");if rc==0{t.Fatal("legacy writer after promotion",string(err))}
  out,err,rc:=cli(t,p,"ledger","status","--run-id",run,"--json");if rc!=0{t.Fatal("historical read unavailable",string(err))};var historical map[string]any;_ =json.Unmarshal(out,&historical)
  if historical["historical"]!=true||historical["current_authority"]!="gauge"||historical["current_acceptance"]!="unavailable"{t.Fatalf("legacy state represented current Go state: %s",out)}
  for i,raw:=range originals{got,_:=os.ReadFile(filepath.Join(p,".eidolons/.ledger",run,"events",fmt.Sprintf("%d.json",i+1)));if !bytes.Equal(raw,got){t.Fatal("promotion changed original")}}
  // Another legacy root with coincident event identity shares one DB, not a store per root.
  _,err,rc=cli(t,p,"ledger","record","--run-id","other-root","--type","probe","--event-id",before.Legacy[run][0].ID);if rc!=0{t.Fatal(string(err))}
  if e:=s.Import("other-root");e!=nil{t.Fatal(e)};if len(readStore(t,p).Roots)!=2{t.Fatal("legacy root identities collapsed")}
 })}
 t.Run("inventory drift",func(t *testing.T){p:=t.TempDir();run:=legacyFixture(t,p,"legacy");s:=service(t,p);if e:=s.Init();e!=nil{t.Fatal(e)};if e:=s.Import(run);e!=nil{t.Fatal(e)};_,err,rc:=cli(t,p,"ledger","record","--run-id",run,"--type","new");if rc!=0{t.Fatal("staging stole legacy authority",string(err))};before:=readStore(t,p);if s.Promote(run)==nil{t.Fatal("drifting inventory promoted")};if s.Import(run)==nil{t.Fatal("changed inventory silently replaced")};if !reflect.DeepEqual(before,readStore(t,p)){t.Fatal("failed promotion changed import")}})
 t.Run("layout collision",func(t *testing.T){p:=t.TempDir();_,err,rc:=cli(t,p,"ledger","record","--run-id",".gauge-controller-v1","--type","probe");if rc!=0{t.Fatal(string(err))};before,_:=os.ReadFile(filepath.Join(p,".eidolons/.ledger/.gauge-controller-v1/events/1.json"));if service(t,p).Init()==nil{t.Fatal("legacy path overwritten")};after,_:=os.ReadFile(filepath.Join(p,".eidolons/.ledger/.gauge-controller-v1/events/1.json"));if !bytes.Equal(before,after){t.Fatal("collision damaged history")}})
}

func TestV406T04_Invalid(t *testing.T){
 data,e:=os.ReadFile(filepath.Join(repo(t),"cli/tests/fixtures/journal/invalid.json"));if e!=nil{t.Fatal(e)}
 var mutations []struct{Name string `json:"name"`;Raw *string `json:"raw"`;Replace map[string]any `json:"replace"`;Reseal *bool `json:"reseal"`};if e=json.Unmarshal(data,&mutations);e!=nil{t.Fatal(e)}
 for _,m:=range mutations{t.Run(m.Name,func(t *testing.T){p:=t.TempDir();run:=legacyFixture(t,p,"legacy");s:=service(t,p);if e=s.Init();e!=nil{t.Fatal(e)};path:=filepath.Join(p,".eidolons/.ledger",run,"events/2.json");raw,_:=os.ReadFile(path)
  if m.Raw!=nil{raw=[]byte(*m.Raw)}else{var obj map[string]any;_ =json.Unmarshal(raw,&obj);for k,v:=range m.Replace{obj[k]=v};raw,_=json.Marshal(obj);if m.Reseal==nil||*m.Reseal{cmd:=exec.Command("python3","-c",`import json,sys,hashlib,subprocess
x=json.loads(sys.argv[1]);x.pop('event_digest',None);p=subprocess.run(['jq','-cS','.'],input=json.dumps(x).encode(),capture_output=True,check=True);x['event_digest']=hashlib.sha256(p.stdout).hexdigest();print(json.dumps(x))`,string(raw));raw,e=cmd.Output();if e!=nil{t.Fatal(e)}}}
  if e=os.WriteFile(path,raw,0600);e!=nil{t.Fatal(e)};before:=readStore(t,p);if s.Import(run)==nil{t.Fatal("invalid history imported")};if !reflect.DeepEqual(before,readStore(t,p)){t.Fatal("invalid import published partial state")};after,_:=os.ReadFile(path);if !bytes.Equal(raw,after){t.Fatal("invalid history rewritten")}
 })}
}

func TestV406T04_Recovery(t *testing.T){
 for _,cut:=range []string{"pending","committed"}{t.Run(cut,func(t *testing.T){p:=t.TempDir();run:=legacyFixture(t,p,"legacy");s:=service(t,p);if e:=s.Init();e!=nil{t.Fatal(e)};if e:=s.Import(run);e!=nil{t.Fatal(e)}
  broken:=controller.New(p,controller.Options{Timeout:time.Second,Cut:func(phase string)error{if phase==cut{return errors.New("interrupted transfer")};return nil}})
  if broken.Promote(run)==nil{t.Fatal("cut did not interrupt")}
  if _,e:=s.Status(run);e==nil{t.Fatal("incomplete transfer exposed managed state")}
  _,_,rc:=cli(t,p,"ledger","record","--run-id",run,"--type","blocked");if rc==0{t.Fatal("pending transfer reopened legacy writes")}
  if e:=s.Recover(run);e!=nil{t.Fatal(e)};if _,e:=s.Status(run);e!=nil{t.Fatal("explicit recovery",e)}
 })}
}

func TestV406T04_Barrier(t *testing.T){
 p:=t.TempDir();run:=legacyFixture(t,p,"legacy");s:=service(t,p);if e:=s.Init();e!=nil{t.Fatal(e)}
 start:=make(chan struct{});errorsCh:=make(chan error,2);var wg sync.WaitGroup
 for i:=0;i<2;i++{wg.Add(1);go func(){defer wg.Done();<-start;errorsCh<-service(t,p).Import(run)}()};close(start);wg.Wait();close(errorsCh);for e:=range errorsCh{if e!=nil{t.Fatal("concurrent same import",e)}}
 reached:=make(chan struct{});release:=make(chan struct{});first:=controller.New(p,controller.Options{Timeout:time.Second,Cut:func(phase string)error{if phase=="pending"{close(reached);<-release};return nil}})
 done:=make(chan error,1);go func(){done<-first.Promote(run)}();<-reached
 other:=service(t,p);if other.Promote(run)==nil{t.Fatal("competing promoter stole lock")}
 _,_,rc:=cli(t,p,"ledger","record","--run-id",run,"--type","racing");if rc==0{t.Fatal("Bash raced into promoted journal")};close(release);if e:=<-done;e!=nil{t.Fatal(e)}
 if len(readStore(t,p).Legacy[run])!=2{t.Fatal("split inventory")}
 // Removing or corrupting the marker never authorizes Go mutation either.
 marker:=filepath.Join(p,".eidolons/.ledger",run,".writer-authority.json");if e:=os.Remove(marker);e!=nil{t.Fatal(e)}
 if _,e:=s.ExecuteFixture(context.Background(),run,"forbidden",contract.FixtureInput{Outcome:"pass"});e==nil{t.Fatal("Go writer ignored authority marker")}
}

type fakeAdapter struct{calls atomic.Int32; modelCalls atomic.Int32}
func(f *fakeAdapter)Observe(_ context.Context,in contract.FixtureInput)(contract.ObservationResult,error){f.calls.Add(1);return contract.ObservationResult{Outcome:in.Outcome,ObservedModel:"unknown",ModelCalls:0},nil}

func TestV406T06(t *testing.T){
 p:=t.TempDir();fake:=&fakeAdapter{};var ids atomic.Int32;s:=controller.New(p,controller.Options{Timeout:time.Second,Adapter:fake,Clock:func()time.Time{return time.Date(2026,9,22,1,2,3,0,time.UTC)},IDs:func()string{return fmt.Sprintf("allocated-%d",ids.Add(1))}})
 if e:=s.Init();e!=nil{t.Fatal(e)};if e:=s.InitRoot("root");e!=nil{t.Fatal(e)}
 first,e:=s.ExecuteFixture(context.Background(),"root","receipt-request",contract.FixtureInput{Outcome:"pass"});if e!=nil{t.Fatal(e)}
 retry,e:=s.ExecuteFixture(context.Background(),"root","receipt-request",contract.FixtureInput{Outcome:"pass"});if e!=nil||!reflect.DeepEqual(first,retry){t.Fatal("retry changed observation",e)}
 if _,e=s.ExecuteFixture(context.Background(),"root","receipt-request",contract.FixtureInput{Outcome:"fail"});e==nil{t.Fatal("conflicting retry accepted")}
 if _,e=s.Status("root");e!=nil{t.Fatal(e)}
 if fake.calls.Load()!=1||fake.modelCalls.Load()!=0||first.ModelCalls!=0||first.ObservedModel!="unknown"||first.Accepted||first.Grade!="fixture-only"||first.Timestamp!="2026-09-22T01:02:03Z"{t.Fatalf("bookkeeping/provenance violation: %+v calls=%d",first,fake.calls.Load())}
}

func TestV406T08(t *testing.T){
 p:=t.TempDir();s:=service(t,p);if e:=s.Init();e!=nil{t.Fatal(e)};if e:=s.InitRoot("root");e!=nil{t.Fatal(e)}
 initial:=readStore(t,p).Roots["root"];db,e:=store.Open(filepath.Join(p,".eidolons/.ledger/.gauge-controller-v1/state.db"),time.Second);if e!=nil{t.Fatal(e)}
 if e=db.Update("root",initial.Generation,func(tx *store.Tx)error{r:=tx.Root();r.PolicyRefs=[]string{"policy-retained"};r.Intents=[]string{"intent-retained"};r.Evidence=[]string{"evidence-retained"};r.Binding.Candidate="candidate-retained";return tx.SetRoot(r)});e!=nil{t.Fatal(e)};db.Close()
 before:=readStore(t,p).Roots["root"]
 if e:=s.Replace("root","worker-replacement","",true);e!=nil{t.Fatal(e)};after:=readStore(t,p).Roots["root"]
 if after.Binding.Worker!="worker-replacement"||after.Binding.Environment!=before.Binding.Environment||after.ID!=before.ID||after.Binding.Authority!=before.Binding.Authority{t.Fatal("process replacement changed durable identity")}
 if e:=s.Replace("root","","environment-replacement",true);e!=nil{t.Fatal(e)};final:=readStore(t,p).Roots["root"]
 if final.Binding.Worker!=after.Binding.Worker||final.Binding.Environment!="environment-replacement"||final.ID!=before.ID||!reflect.DeepEqual(final.PolicyRefs,before.PolicyRefs)||!reflect.DeepEqual(final.Intents,before.Intents)||!reflect.DeepEqual(final.Evidence,before.Evidence)||final.Binding.Candidate!=before.Binding.Candidate{t.Fatal("environment replacement reset durable references")}
 if e:=s.Replace("root","unsupported","",false);e==nil{t.Fatal("unsupported reconstruction accepted")};if !reflect.DeepEqual(final,readStore(t,p).Roots["root"]){t.Fatal("blocked reconstruction mutated root")}
}
