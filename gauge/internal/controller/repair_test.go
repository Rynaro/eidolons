package controller_test

import (
 "bufio"
 "bytes"
 "context"
 "fmt"
 "os"
 "os/exec"
 "path/filepath"
 "reflect"
 "testing"
 "time"

 "github.com/Rynaro/eidolons/gauge/internal/contract"
 "github.com/Rynaro/eidolons/gauge/internal/controller"
)

func TestV406RepairMissingMarker(t *testing.T) {
 for _,imported := range []bool{true,false} { t.Run(fmt.Sprint(imported),func(t *testing.T){
  p:=t.TempDir(); s:=service(t,p); if e:=s.Init();e!=nil{t.Fatal(e)}
  run:="new-root"
  if imported {run=legacyFixture(t,p,"legacy");if e:=s.Import(run);e!=nil{t.Fatal(e)};if e:=s.Promote(run);e!=nil{t.Fatal(e)}} else if e:=s.InitRoot(run);e!=nil{t.Fatal(e)}
  if _,e:=s.Status(run);e!=nil{t.Fatal(e)}
  marker:=filepath.Join(p,".eidolons/.ledger",run,".writer-authority.json");raw,e:=os.ReadFile(marker);if e!=nil{t.Fatal(e)}
  if e=os.Remove(marker);e!=nil{t.Fatal(e)}
  _,err,rc:=cli(t,p,"ledger","record","--run-id",run,"--type","probe","--event-id","marker-lost")
  if rc==0{t.Error("F001 missing marker reopened Bash writes",string(err))}
  if _,e=s.ExecuteFixture(context.Background(),run,"lost",contract.FixtureInput{Outcome:"pass"});e==nil{t.Error("Go mutation allowed missing marker")}
  if e=os.WriteFile(marker,raw,0600);e!=nil{t.Fatal(e)}
  if rc!=0 {if _,e=s.Status(run);e!=nil{t.Fatal("unchanged inventory restoration control",e)}}
  // Simulate independent historical-file drift, without asking the guarded
  // writer to violate ownership: preserving valid JSON still changes bytes.
  if imported {event:=filepath.Join(p,".eidolons/.ledger",run,"events/1.json");b,e:=os.ReadFile(event);if e!=nil{t.Fatal(e)};if e=os.WriteFile(event,append(b,'\n'),0600);e!=nil{t.Fatal(e)}
   if _,e=s.Status(run);e==nil{t.Error("F001 restored marker hid divergent legacy inventory")}
   if e=s.Promote(run);e==nil{t.Error("idempotent promotion hid divergent inventory")}
   if e=s.Recover(run);e==nil{t.Error("recovery hid divergent inventory")}
  }
  // The shared instance must not claim unrelated or merely frozen imports.
  for _,other:=range []string{"ordinary","frozen"} {_,err,rc=cli(t,p,"ledger","record","--run-id",other,"--type","probe","--event-id","first");if rc!=0{t.Fatal("other root blocked",string(err))}}
  if e=s.Import("frozen");e!=nil{t.Fatal(e)}
  _,err,rc=cli(t,p,"ledger","record","--run-id","frozen","--type","probe","--event-id","second");if rc!=0{t.Fatal("staged import stole Bash authority",string(err))}
 })}
}

func TestV406RepairImportedReconstruction(t *testing.T) {
 p:=t.TempDir();run:=legacyFixture(t,p,"legacy");s:=service(t,p);if e:=s.Init();e!=nil{t.Fatal(e)};if e:=s.Import(run);e!=nil{t.Fatal(e)};if e:=s.Promote(run);e!=nil{t.Fatal(e)}
 before:=readStore(t,p)
 if before.Roots[run].Manifest.Adapter!="unknown"{t.Error("F002 imported adapter provenance is not unknown")}
 for _,replacement:=range [][2]string{{"replacement-worker",""},{"","replacement-environment"}} {
  if e:=s.Replace(run,replacement[0],replacement[1],true);e==nil{t.Error("F002 imported native-unobserved history accepted fixture reconstruction")}
 }
 if !reflect.DeepEqual(before,readStore(t,p)){t.Error("refused imported reconstruction changed durable state")}
 if e:=s.InitRoot("fixture");e!=nil{t.Fatal(e)}
 if e:=s.Replace("fixture","worker","",true);e!=nil{t.Fatal("fixture positive control",e)}
 if e:=s.Replace("fixture","","environment",true);e!=nil{t.Fatal("environment positive control",e)}
}

// The parent independently kills this OS process at externally acknowledged
// boundaries. No error-return cut or parent goroutine performs the crash.
func TestV406RepairPromotionChild(t *testing.T) {
 p:=os.Getenv("V406_PROCESS_PROJECT");if p==""{t.Skip("child entry point")}
 mode:=os.Getenv("V406_PROCESS_MODE");run:=os.Getenv("V406_PROCESS_ROOT")
 pause:=func(){fmt.Println("READY");for {time.Sleep(time.Hour)}}
 if mode=="before"{pause()}
 s:=controller.New(p,controller.Options{Timeout:100*time.Millisecond,Cut:func(phase string)error{if phase==mode{pause()};return nil}})
 if e:=s.Promote(run);e!=nil{fmt.Fprintln(os.Stderr,e);os.Exit(3)}
 if mode=="published"{pause()}
 os.Exit(0)
}

func TestV406RepairPromotionProcessKill(t *testing.T) {
 for _,phase:=range []string{"before","pending","committed","published"} {t.Run(phase,func(t *testing.T){
  p:=t.TempDir();run:=legacyFixture(t,p,"legacy");s:=service(t,p);if e:=s.Init();e!=nil{t.Fatal(e)};if e:=s.Import(run);e!=nil{t.Fatal(e)}
  before:=readStore(t,p);exe,e:=os.Executable();if e!=nil{t.Fatal(e)}
  child:=func(mode string)*exec.Cmd{c:=exec.Command(exe,"-test.run=^TestV406RepairPromotionChild$");c.Env=append(os.Environ(),"V406_PROCESS_PROJECT="+p,"V406_PROCESS_ROOT="+run,"V406_PROCESS_MODE="+mode);return c}
  c:=child(phase);out,e:=c.StdoutPipe();if e!=nil{t.Fatal(e)};var stderr bytes.Buffer;c.Stderr=&stderr
  if e=c.Start();e!=nil{t.Fatal(e)}
  reaped:=false;defer func(){if !reaped{_ =c.Process.Kill();_ =c.Wait()}}()
  ready:=make(chan string,1);go func(){line,_:=bufio.NewReader(out).ReadString('\n');ready<-line}()
  select{case line:=<-ready:if line!="READY\n"{t.Fatalf("child barrier %q %s",line,stderr.String())};case <-time.After(15*time.Second):t.Fatal("child barrier timeout")}
  if phase=="pending"||phase=="committed" {
   contender:=child("contender");if b,e:=contender.CombinedOutput();e==nil{t.Fatalf("independent promoter stole ownership: %s",b)}
   _,_,rc:=cli(t,p,"ledger","record","--run-id",run,"--type","racing");if rc==0{t.Fatal("independent Bash writer stole ownership")}
  }
  if e=c.Process.Kill();e!=nil{t.Fatal(e)};if e=c.Wait();e==nil{t.Fatal("child was not killed")};reaped=true
  t.Logf("independently killed and reaped promoter pid=%d at %s",c.Process.Pid,phase)
  if phase=="pending"||phase=="committed" {
   if _,e=s.Status(run);e==nil{t.Fatal("crashed lock accepted")}
   if e=s.Recover(run);e==nil{t.Fatal("recovery stole unresolved process lock")}
   // All children are now reaped and the synchronous Bash writer completed.
   // This is explicit operator recovery after established quiescence.
   lock:=filepath.Join(p,".eidolons/.ledger",run,".append-lock")
   if e=os.Remove(filepath.Join(lock,"owner"));e!=nil{t.Fatal(e)};if e=os.Remove(lock);e!=nil{t.Fatal(e)}
   if e=s.Recover(run);e!=nil{t.Fatal("quiescent recovery",e)}
  } else if phase=="before" {if e=s.Promote(run);e!=nil{t.Fatal("pre-publication positive control",e)}}
  status,e:=s.Status(run);if e!=nil{t.Fatal(e)}
  if status.Root.Phase!="active"||!reflect.DeepEqual(before.Legacy[run],status.Imported){t.Fatal("recovery changed imported bytes/IDs/grades")}
  if e=s.Promote(run);e!=nil{t.Fatal("exactly-once retry",e)}
  if _,e=s.ExecuteFixture(context.Background(),run,"post-recovery",contract.FixtureInput{Outcome:"pass"});e!=nil{t.Fatal("recovered fixture positive control",e)}
  _,_,rc:=cli(t,p,"ledger","record","--run-id",run,"--type","after-kill");if rc==0{t.Fatal("legacy authority reopened after recovery")}
 })}
}
