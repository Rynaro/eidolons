"""V4-05 acceptance anchors: production negatives and authenticated pure controls."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "cli/tests/fixtures/completion"
BASH = os.environ.get("LEDGER_TEST_BASH", "bash")


def require(value, message):
    if not value:
        raise AssertionError(message)


def module():
    spec = importlib.util.spec_from_file_location("ledger_completion", REPO / "cli/src/ledger_completion.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


class Project:
    def __init__(self, directory, git=True):
        self.root = Path(directory) / "project"
        self.root.mkdir()
        self.outside = Path(directory)
        self.env = dict(os.environ, EIDOLONS_HOME=str(self.outside / "home"),
                        EIDOLONS_NEXUS=str(REPO), EIDOLONS_UI="plain", TEST_MODE="one")
        self.cli = [BASH, str(REPO / "cli/src/ledger.sh")]
        self.artifact = self.outside / "evidence.txt"
        self.artifact.write_text("observed checks\n")
        self.criteria = {"schema_version": "1.0", "required_checks": [{"id": "tests", "oracle_id": "tests@1"}],
                         "required_untracked": ["required.txt"], "environment": ["TEST_MODE"],
                         "configuration": ["config.json"]}
        (self.root / "criteria.json").write_text(json.dumps(self.criteria))
        (self.root / "source.txt").write_text("source\n")
        (self.root / "config.json").write_text('{"mode":"one"}\n')
        (self.root / ".gitignore").write_text("required.txt\n.eidolons/.ledger/\n")
        (self.root / "required.txt").write_text("required untracked\n")
        (self.root / "link").symlink_to("source.txt")
        if git:
            self.git("init", "-q")
            self.git("add", ".")
            self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                     "commit", "-qm", "fixture")

    def git(self, *args):
        return subprocess.run(["git"] + list(args), cwd=self.root, env=self.env,
                              capture_output=True, text=True, check=True).stdout.strip()

    def call(self, *args, ok=True, env=None):
        result = subprocess.run(self.cli + list(args), cwd=self.root, env=env or self.env,
                                text=True, capture_output=True, timeout=40)
        if ok:
            require(result.returncode == 0, (args, result.returncode, result.stderr))
        else:
            require(result.returncode != 0 and not result.stdout.strip(),
                    ("expected rejection", args, result.returncode, result.stdout, result.stderr))
        return result

    def capture_candidate(self, identity="candidate"):
        return self.call("candidate", "--run-id", "run", "--criteria", "criteria.json",
                         "--integration-base", "HEAD", "--event-id", identity)

    def complete(self, verdict="pass", identity=None):
        args = ["complete", "--run-id", "run", "--candidate", "candidate", "--check-id", "tests",
                "--artifact", str(self.artifact), "--checker", "checker-label", "--scope", "tests",
                "--verdict", verdict]
        if identity:
            args += ["--event-id", identity]
        return self.call(*args)

    def status(self):
        return json.loads(self.call("status", "--run-id", "run", "--json").stdout)

    def events(self):
        return self.root / ".eidolons/.ledger/run/events"

    def bytes(self):
        return {p.name: p.read_bytes() for p in self.events().glob("*.json")}


def legacy_floor(p):
    # The sandbox's RED gate uses only established, valid production commands.
    p.call("complete", "--run-id", "run", "--artifact", str(p.artifact), "--checker", "renamed-maker",
           "--scope", "tests", "--verdict", "pass")
    result = p.status()
    require(result["completion"] == "not-complete", "manual label incorrectly received independent completion")


def pure():
    m = module()
    fixture = json.loads((FIXTURES / "control.json").read_text())
    contexts = {"receipt-1": m.AuthenticatedContext("maker-1", "checker-1", "qualified")}
    return m, fixture, contexts


def evaluate(m, fixture, contexts=None):
    return m.project(fixture["candidate"], fixture["observations"], fixture["current_identity"],
                     fixture["evidence"], contexts or {})


def accepted(result):
    return result["acceptance_status"]["status"] == "accepted"


def latest(p):
    p.capture_candidate()
    for outcome in ["pass", "fail", "pass"]:
        p.complete(outcome)
        result = p.status()
        require(result["checks"][0]["outcome"] == outcome, ("production latest outcome", result))
        require(not accepted(result), "production labels upgraded trust")
    m, f, ctx = pure()
    require(accepted(evaluate(m, f, ctx)), "qualified positive control rejected")
    for sequence, outcome in [(2, "fail"), (3, "pass")]:
        obs = copy.deepcopy(f["observations"][0])
        obs.update(event_id="receipt-%s" % sequence, sequence=sequence, outcome=outcome,
                   checker_invocation_id="checker-%s" % sequence)
        f["observations"].append(obs)
        f["evidence"][obs["event_id"]] = "verified"
        ctx[obs["event_id"]] = m.AuthenticatedContext("maker-1", obs["checker_invocation_id"], "qualified")
        require(accepted(evaluate(m, f, ctx)) == (outcome == "pass"), "pass-fail-pass projection failed")
    other = copy.deepcopy(f["observations"][-1]); other.update(sequence=4, outcome="fail", check_id="unrelated")
    f["observations"].append(other)
    wrong = copy.deepcopy(other); wrong["check_id"] = "tests"; wrong["identity"]["candidate"] = "other"
    f["observations"].append(wrong)
    require(accepted(evaluate(m, f, ctx)), "unrelated historical failure poisoned current evidence")


def candidate(p):
    p.capture_candidate()
    original = p.bytes()
    p.capture_candidate()
    require(p.bytes() == original, "typed retry regenerated volatile facts")
    p.complete(identity="check")
    before = p.bytes(); p.complete(identity="check")
    require(p.bytes() == before, "typed completion retry changed bytes")
    require(p.status()["candidate_status"]["status"] == "current", "unchanged candidate stale")
    cases = [
        ("source.txt", "different\n"), ("required.txt", "changed ignored required input\n"),
        ("config.json", '{"mode":"two"}\n'), ("criteria.json", json.dumps(dict(p.criteria, note="changed"))),
    ]
    for name, value in cases:
        path = p.root / name; old = path.read_bytes(); path.write_text(value)
        result = p.status()
        require(result["candidate_status"]["status"] != "current", (name, "mutation not detected"))
        p.call("candidate", "--run-id", "run", "--criteria", "criteria.json", "--integration-base", "HEAD",
               "--event-id", "candidate", ok=False)
        require(p.bytes() == before, "conflicting capture changed history")
        path.write_bytes(old)
    source = p.root / "source.txt"; mode = source.stat().st_mode; source.chmod(0o755)
    require(p.status()["candidate_status"]["status"] != "current", "mode mutation not detected")
    source.chmod(mode)
    link = p.root / "link"; link.unlink(); link.symlink_to("required.txt")
    require(p.status()["candidate_status"]["status"] != "current", "symlink mutation not detected")
    link.unlink(); link.symlink_to(p.artifact)
    require(p.status()["candidate_status"]["status"] != "current", "external symlink accepted")
    link.unlink(); link.symlink_to("source.txt")
    p.env["TEST_MODE"] = "two"
    require(p.status()["candidate_status"]["status"] != "current", "environment mutation not detected")
    p.env["TEST_MODE"] = "one"
    p.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--allow-empty", "-qm", "base change")
    require(p.status()["candidate_status"]["status"] != "current", "integration base mutation not detected")
    m, f, ctx = pure()
    require(accepted(evaluate(m, f, ctx)), "candidate positive control failed")
    f["current_identity"]["candidate"] = "changed"
    require(not accepted(evaluate(m, f, ctx)), "trusted stale candidate accepted")


def ancestors(p):
    # R02: permissions and path kinds of every input ancestor affect execution.
    failures = []
    for category in ("tracked", "discovered", "required-ignored", "symlink-target"):
        with tempfile.TemporaryDirectory(prefix="completion-ancestors-") as directory:
            q = Project(directory)
            parent = q.root / "inputs"
            nested = parent / "nested"
            nested.mkdir(parents=True)
            leaf = nested / "input.txt"
            leaf.write_text("input bytes\n")
            with (q.root / ".gitignore").open("a") as stream:
                stream.write("alternate/\n")
                if category in ("required-ignored", "symlink-target"):
                    stream.write("inputs\n")
            if category == "required-ignored":
                q.criteria["required_untracked"].append("inputs/nested/input.txt")
                (q.root / "criteria.json").write_text(json.dumps(q.criteria))
            if category == "symlink-target":
                (q.root / "link").unlink()
                (q.root / "link").symlink_to("inputs/nested/input.txt")
            q.git("add", ".gitignore", "criteria.json", "link")
            if category == "tracked":
                q.git("add", "inputs/nested/input.txt")
            q.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                  "commit", "-qm", "ancestor fixture")
            q.capture_candidate()
            q.complete(identity="receipt")
            before = q.bytes()

            def check(step, current):
                result = q.status()
                actual = result["candidate_status"]["status"]
                if (actual == "current") != current:
                    failures.append((category, step, "current" if current else "stale", actual))
                if not current and "candidate-unavailable-or-stale" not in result["acceptance_status"]["reasons"]:
                    failures.append((category, step, "dependent evidence was not invalidated"))
                require(q.bytes() == before, (category, step, "status changed journal bytes"))

            check("unchanged", True)
            for ancestor in (parent, nested):
                mode = ancestor.stat().st_mode
                ancestor.chmod(0o700)
                check(str(ancestor.relative_to(q.root)) + " chmod", False)
                ancestor.chmod(mode)
                check("mode restored", True)
            parent.rename(q.root / "alternate")
            parent.symlink_to("alternate", target_is_directory=True)
            check("internal ancestor symlink", False)
            (q.root / "alternate/nested/input.txt").write_text("changed bytes\n")
            check("content control", False)
            (q.root / "alternate/nested/input.txt").write_text("input bytes\n")
            parent.unlink()
            (q.root / "alternate").rename(parent)
            check("all restored", True)
    require(not failures, failures)


def legacy_retry(p):
    # Freeze the pre-V4-05 wire declaration while preserving its valid v1 digest.
    args = ["complete", "--run-id", "run", "--event-id", "legacy", "--artifact", str(p.artifact),
            "--checker", "checker", "--scope", "tests", "--verdict", "pass"]
    p.call(*args)
    event_path = p.events() / "1.json"
    event = json.loads(event_path.read_text())
    event["observed"].update(independent=True, completion="independently-verified")
    del event["event_digest"]
    canonical = subprocess.run(["jq", "-cS", "."], input=json.dumps(event), text=True,
                               capture_output=True, check=True).stdout.encode()
    import hashlib
    event["event_digest"] = hashlib.sha256(canonical).hexdigest()
    event_path.write_text(json.dumps(event) + "\n")
    before = p.bytes()
    require(p.status()["execution_provenance"]["status"] == "self-attested", "legacy trust upgraded")
    p.call(*args)
    require(p.bytes() == before, "exact legacy retry rewrote original declarations")
    for flag, changed in (("--verdict", "fail"), ("--checker", "other"), ("--scope", "other")):
        conflict = list(args)
        conflict[conflict.index(flag) + 1] = changed
        p.call(*conflict, ok=False)
        require(p.bytes() == before, (flag, "conflict changed legacy bytes"))
    original = p.artifact.read_bytes()
    p.artifact.write_text("changed evidence\n")
    p.call(*args, ok=False)
    require(p.bytes() == before, "digest conflict changed legacy bytes")
    p.artifact.write_bytes(original)
    other = p.outside / "other-evidence.txt"
    other.write_bytes(original)
    conflict = list(args)
    conflict[conflict.index("--artifact") + 1] = str(other)
    p.call(*conflict, ok=False)
    # Generic record must retain its strict, complete payload comparison.
    p.call("record", "--run-id", "run", "--event-id", "legacy", "--type", "checked",
           "--requested", json.dumps(event["requested"]),
           "--observed", json.dumps(dict(event["observed"], independent=False)), ok=False)
    p.call(*args)
    require(p.bytes() == before, "restored retry changed legacy bytes")
    result = p.status()
    require(result["completion"] == "not-complete" and not accepted(result) and
            result["execution_provenance"]["status"] == "self-attested", "legacy retry upgraded trust")


def provenance(p):
    legacy_floor(p)
    for checker in ["maker", "renamed-maker", "different-checker"]:
        p.call("complete", "--run-id", "run", "--artifact", str(p.artifact), "--checker", checker,
               "--scope", "tests", "--verdict", "pass")
        require(not accepted(p.status()), "label conferred acceptance")
    p.call("record", "--run-id", "run", "--type", "checked", "--observed",
           '{"completion":"independently-verified","independent":true,"trusted":true,"verdict":"pass"}')
    p.env["EIDOLONS_TRUSTED_CHECKER"] = "1"
    require(not accepted(p.status()), "forged trust conferred acceptance")
    m, f, ctx = pure()
    require(accepted(evaluate(m, f, ctx)), "authenticated fixture rejected")
    require(not accepted(evaluate(m, f)), "serialized provenance trusted")
    for auth in [m.AuthenticatedContext("", "checker-1", "qualified"),
                 m.AuthenticatedContext("maker-1", "maker-1", "qualified"),
                 m.AuthenticatedContext("maker-1", "checker-1", "unknown")]:
        require(not accepted(evaluate(m, f, {"receipt-1": auth})), "missing/same/unknown provenance accepted")
    p.call("record", "--run-id", "run", "--type", "completion-check", "--observed", json.dumps(f["observations"][0]))
    require(not accepted(p.status()), "copied positive fixture gained production trust")


def views(p):
    p.capture_candidate(); p.complete("fail")
    p.call("capture", "--run-id", "run", "--event-id", "view")
    capture = p.bytes(); p.call("capture", "--run-id", "run", "--event-id", "view")
    require(p.bytes() == capture, "historical capture retry changed bytes")
    for fmt in ["json", "text", "markdown"]:
        args = ["render", "--run-id", "run", "--event-id", "view", "--format", fmt]
        first = p.call(*args).stdout
        require(first == p.call(*args).stdout, "view used a rendering clock")
        target = p.outside / ("view." + fmt); target.write_text(first)
        p.call(*args, "--compare", str(target))
        target.write_text(first + "edited\n")
        p.call(*args, "--compare", str(target), ok=False)
    original = p.call("render", "--run-id", "run", "--event-id", "view", "--format", "json").stdout
    doc = json.loads(original)
    require(doc["historical"] is True and doc["captured_at"] and doc["capture_invocation_id"], "view lacks captured facts")
    p.complete("pass")
    require(p.call("render", "--run-id", "run", "--event-id", "view", "--format", "json").stdout == original,
            "later state rewrote historical view")
    p.call("capture", "--run-id", "run", "--event-id", "view-new")
    newer = p.call("render", "--run-id", "run", "--event-id", "view-new", "--format", "json").stdout
    require(newer != original and json.loads(newer)["checks"][0]["outcome"] == "pass", "new canonical outcome ignored")
    ref = p.outside / "reference.json"
    ref.write_text(json.dumps({"schema_version":"1.0", "kind":"completion-view-reference", "run_id":"run", "event_id":"view"}))
    augment = [BASH, str(REPO / "cli/src/augment.sh"), "evidence", str(ref)]
    r = subprocess.run(augment, cwd=p.root, env=p.env, capture_output=True, text=True)
    require(r.returncode == 0 and r.stdout == original, "augment canonical shim differs")
    for invalid in [[], [{"status":"pass"}], [{"status":"fail"}], {}]:
        ref.write_text(json.dumps(invalid))
        r = subprocess.run(augment, cwd=p.root, env=p.env, capture_output=True, text=True)
        require(r.returncode != 0 and not r.stdout and "canonical" in r.stderr.lower(), "legacy array or malformed reference accepted")
    require(not (p.root / ".eidolons/.product-leap").exists(), "evidence renderer initialized augment state")
    m, f, ctx = pure()
    result = evaluate(m, f, ctx)
    golden = json.loads((FIXTURES / "expected.json").read_text())
    require({k: result[k] for k in golden} == golden, "pure frozen projection differs")
    historical = m.historical_view({"event_id":"frozen-view", "timestamp":"2026-01-02T03:04:05Z",
        "observed":{"kind":"projection", "contract_version":"1.0", "inputs":f,
                    "capture":{"invocation_id":"frozen-invocation"}}})
    require(historical["captured_at"] == "2026-01-02T03:04:05Z" and not accepted(historical),
            "historical fixture restored trust or replaced capture clock")


def required(p):
    p.capture_candidate()
    result = p.status(); require(result["checks"][0]["outcome"] == "missing", "missing check hidden")
    p.complete("cancelled"); require(p.status()["checks"][0]["outcome"] == "cancelled", "cancellation hidden")
    p.complete("pass"); require(p.status()["artifact_integrity"]["status"] == "verified", "valid artifact not verified")
    p.artifact.write_text("changed\n"); require(p.status()["artifact_integrity"]["status"] == "changed", "changed artifact accepted")
    p.artifact.unlink(); require(p.status()["artifact_integrity"]["status"] == "missing", "absent artifact accepted")
    m, f, ctx = pure()
    require(accepted(evaluate(m, f, ctx)), "positive mandatory set failed")
    variants = []
    empty = copy.deepcopy(f); empty["candidate"]["required_checks"] = []; variants.append(empty)
    absent = copy.deepcopy(f); absent["observations"] = []; variants.append(absent)
    for outcome in ["fail", "cancelled", "skipped", "unknown"]:
        item = copy.deepcopy(f); item["observations"][0]["outcome"] = outcome; variants.append(item)
    for key in ["candidate", "criteria", "environment", "configuration", "integration_base"]:
        item = copy.deepcopy(f); item["observations"][0]["identity"][key] = "stale"; variants.append(item)
    for integrity in ["missing", "changed", "unavailable"]:
        item = copy.deepcopy(f); item["evidence"]["receipt-1"] = integrity; variants.append(item)
    for item in variants:
        require(not accepted(evaluate(m, item, ctx)), ("invalid mandatory set accepted", item))


def grades(p):
    p.capture_candidate(); p.complete()
    result = p.status()
    require(result["artifact_integrity"]["status"] == "verified", "artifact integrity lost")
    require(result["execution_provenance"]["status"] == "self-attested", "manual provenance upgraded")
    require(not accepted(result), "matching digest set acceptance")
    m, f, ctx = pure(); result = evaluate(m, f, ctx)
    require(result["artifact_integrity"]["status"] == "verified" and
            result["execution_provenance"]["status"] == "authenticated-independent" and accepted(result),
            "typed independent positive grades incorrect")


def termination(p):
    p.capture_candidate()
    for kind in ["native-completed", "a2a-completed", "mcp-result"]:
        p.call("record", "--run-id", "run", "--type", kind, "--observed",
               '{"success":true,"status":"completed","completion":"independently-verified"}')
        result = p.status()
        require(not accepted(result) and result["checks"][0]["outcome"] == "missing", "termination supplied acceptance")
    p.complete("fail")
    require(not accepted(p.status()) and p.status()["checks"][0]["outcome"] == "fail", "termination hid failed check")
    m, f, ctx = pure(); require(accepted(evaluate(m, f, ctx)), "valid receipt positive control failed")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="completion-conformance-") as directory:
        globals()[sys.argv[1]](Project(directory, git=sys.argv[1] != "legacy_floor"))
