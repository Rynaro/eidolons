package contract_test

import (
 "encoding/json"
 "os"
 "os/exec"
 "path/filepath"
 "reflect"
 "testing"

 "github.com/Rynaro/eidolons/gauge/internal/contract"
)

func TestV406T01(t *testing.T) {
 first := contract.Binding{Root:"root", Assignment:"assignment", Profile:"vivi", Method:"method-1", Worker:"worker-1", Invocation:"invocation-1", Context:"context-1", Authority:"authority-1", Candidate:"candidate-1", Receipt:"receipt-1", Environment:"environment-1"}
 second := first; second.Method="method-2"
 third := first; third.Worker="worker-2"; third.Invocation="invocation-2"; third.Context="context-2"
 for _, b := range []contract.Binding{first,second,third} { if err:=b.Validate(); err!=nil {t.Fatal(err)} }
 if first.Profile!=third.Profile || first.Worker==third.Worker || first.Context==third.Context || first.Method==second.Method || first.Worker!=second.Worker {t.Fatal("identity collapsed")}
 var round contract.Binding; data,_:=json.Marshal(third); if err:=json.Unmarshal(data,&round); err!=nil || !reflect.DeepEqual(round,third){t.Fatal("identity roundtrip",err)}
 invalid:=first; invalid.Context=""; if invalid.Validate()==nil {t.Fatal("missing context accepted")}
}

func TestV406T07(t *testing.T) {
 for _, pair:=range [][2]string{{"history","receipt"},{"context","context-reference"},{"knowledge","note"},{"policy","policy"}} {
  r:=contract.Record{ID:"id",Family:pair[0],Kind:pair[1],Body:json.RawMessage(`{"value":"durable"}`)}
  if err:=r.Validate();err!=nil{t.Fatal(err)}
  data,_:=json.Marshal(r);var rr contract.Record;if err:=json.Unmarshal(data,&rr);err!=nil || !reflect.DeepEqual(rr,r){t.Fatal("record roundtrip",err)}
 }
 for _,pair:=range [][2]string{{"policy","note"},{"history","context-reference"},{"context","receipt"},{"unknown","policy"}} {
  r:=contract.Record{ID:"wrong",Family:pair[0],Kind:pair[1],Body:json.RawMessage(`{}`)}
  if r.Validate()==nil{t.Fatalf("substitution accepted: %v",pair)}
 }
}

func TestV406T09(t *testing.T) {
 base:=contract.Manifest{Version:1,RequestedModel:"requested",ObservedModel:"unknown",Harness:"native@1",Adapter:"fixture@1",Methods:[]string{"method@1"},Environment:"environment",PolicyRefs:[]string{"policy"}}
 first,err:=base.Identity();if err!=nil{t.Fatal(err)}
 changes:=[]func(*contract.Manifest){func(m *contract.Manifest){m.RequestedModel="other"},func(m *contract.Manifest){m.ObservedModel="observed"},func(m *contract.Manifest){m.Harness="native@2"},func(m *contract.Manifest){m.Adapter="fixture@2"},func(m *contract.Manifest){m.Methods=[]string{"other"}},func(m *contract.Manifest){m.Environment="other"},func(m *contract.Manifest){m.PolicyRefs=[]string{"other"}}}
 seen:=map[string]bool{first:true};for _,change:=range changes{m:=base;change(&m);id,e:=m.Identity();if e!=nil||seen[id]{t.Fatal("manifest constituent ignored",id,e)};seen[id]=true}
 if base.ObservedModel!="unknown"{t.Fatal("requested model became observed")}
 invalid:=base;invalid.Version=999;if _,e:=invalid.Identity();e==nil{t.Fatal("future manifest accepted")}
 invalid=base;invalid.ObservedModel="";if _,e:=invalid.Identity();e==nil{t.Fatal("implicit unknown accepted")}
}

func TestV406T04_ProjectionDifferential(t *testing.T) {
 repo:=os.Getenv("GAUGE_REPO");if repo==""{t.Fatal("GAUGE_REPO required")}
 data,err:=os.ReadFile(filepath.Join(repo,"cli/tests/fixtures/completion/control.json"));if err!=nil{t.Fatal(err)}
 var input contract.ProjectionInput;if err=json.Unmarshal(data,&input);err!=nil{t.Fatal(err)}
 scenarios:=[]contract.ProjectionInput{input}
 failed:=input;failed.Observations=append(append([]contract.Observation{},input.Observations...),input.Observations[0]);failed.Observations[1].EventID="new-failure";failed.Observations[1].Sequence=2;failed.Observations[1].Outcome="fail";failed.Observations[1].CheckerInvocationID="another";scenarios=append(scenarios,failed)
 stale:=input;stale.CurrentIdentity=map[string]string{"candidate":"stale"};scenarios=append(scenarios,stale)
 empty:=input;empty.Candidate.RequiredChecks=nil;scenarios=append(scenarios,empty)
 for _,p:=range scenarios{
  wire,_:=json.Marshal(p)
  script:=`import importlib.util,json,sys
s=importlib.util.spec_from_file_location('completion',sys.argv[1]);m=importlib.util.module_from_spec(s);sys.modules[s.name]=m;s.loader.exec_module(m)
p=json.loads(sys.argv[2]);print(json.dumps(m.project(p['candidate'],p['observations'],p['current_identity'],p['evidence'])))`
  cmd:=exec.Command("python3","-c",script,filepath.Join(repo,"cli/src/ledger_completion.py"),string(wire));cmd.Env=append(os.Environ(),"PYTHONDONTWRITEBYTECODE=1")
  want,e:=cmd.Output();if e!=nil{t.Fatal(e)}
  got,_:=json.Marshal(contract.Project(p));var a,b any;_ = json.Unmarshal(want,&a);_=json.Unmarshal(got,&b);if !reflect.DeepEqual(a,b){t.Fatalf("projection mismatch\nwant %s\ngot %s",want,got)}
  if contract.Project(p).AcceptanceStatus.Status=="accepted"{t.Fatal("wire fixture acquired authority")}
 }
}
