"""Requirement-derived journal probes. Python is a test dependency only."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "cli/tests/fixtures/journal"
BASH = os.environ.get("LEDGER_TEST_BASH", "bash")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def canonical(event):
    # The oracle hashes jq's actual legacy bytes, not Python's number serializer.
    return subprocess.run(["jq", "-cS", "del(.event_digest)"],
                          input=json.dumps(event).encode(), capture_output=True,
                          check=True).stdout


def seal(event):
    event["event_digest"] = hashlib.sha256(canonical(event)).hexdigest()
    return event


class Journal:
    def __init__(self, root):
        self.root = root
        self.env = dict(os.environ, EIDOLONS_HOME=str(root / "home"),
                        EIDOLONS_NEXUS=str(REPO), EIDOLONS_UI="plain",
                        EIDOLONS_LEDGER_LOCK_TIMEOUT="60")
        self.command = [BASH, str(REPO / "cli/src/ledger.sh")]
        self.dispatcher = [str(REPO / "cli/eidolons"), "ledger"]

    def call(self, *args, env=None):
        return subprocess.run(self.command + list(args), cwd=self.root,
                              env=env or self.env, capture_output=True, text=True,
                              timeout=90)

    def record(self, run, identity=None, requested=None, env=None):
        args = ["record", "--run-id", run, "--type", "probe", "--requested",
                json.dumps(requested if requested is not None else {})]
        if identity is not None:
            args += ["--event-id", identity]
        return self.call(*args, env=env)

    def events(self, run):
        return self.root / ".eidolons/.ledger" / run / "events"

    def lock(self, run):
        return self.events(run).parent / ".append-lock"

    def chain(self, run, count):
        paths = list(self.events(run).glob("*.json"))
        require(len(paths) == count, (run, "count", len(paths), count))
        previous = None
        identities = set()
        result = []
        for sequence in range(1, count + 1):
            event = json.loads((self.events(run) / (str(sequence) + ".json")).read_text())
            require(event["sequence"] == sequence, (run, "sequence", event))
            require(event["previous_event_digest"] == previous, (run, "predecessor", sequence))
            require(event["event_id"] not in identities, (run, "identity", event))
            require(event["event_digest"] == hashlib.sha256(canonical(event)).hexdigest(),
                    (run, "digest", sequence))
            identities.add(event["event_id"])
            previous = event["event_digest"]
            result.append(event)
        return result

    def rejected(self, result, text=None):
        require(result.returncode != 0, ("unexpected success", result.stdout, result.stderr))
        require(not result.stdout.strip(), ("successful projection escaped", result.stdout))
        if text:
            require(text in result.stderr.lower(), (text, result.stderr))


def snapshot(root):
    return {str(p.relative_to(root)): (p.read_bytes() if p.is_file() else None)
            for p in root.rglob("*")}


def ordering(j):
    started = time.monotonic()
    for index in range(120):
        result = j.record("ordered", requested={"index": index})
        require(result.returncode == 0, result.stderr)
    j.chain("ordered", 120)
    require(j.call("status", "--run-id", "ordered", "--json").returncode == 0,
            "valid 120-event history rejected")
    print("120-event append and independent verification: %.2fs" % (time.monotonic() - started))


def concurrent(j):
    started = time.monotonic()
    barrier = threading.Barrier(24)
    def writer(index):
        barrier.wait()
        return j.record("concurrent", "id-%s" % index, {"index": index})
    with ThreadPoolExecutor(max_workers=24) as pool:
        results = list(pool.map(writer, range(24)))
    require(all(r.returncode == 0 for r in results), [r.stderr for r in results if r.returncode])
    events = j.chain("concurrent", 24)
    require({e["event_id"]: e["requested"] for e in events} ==
            {"id-%s" % i: {"index": i} for i in range(24)}, "lost or changed accepted identity")
    barrier = threading.Barrier(12)
    def duplicate(index):
        barrier.wait()
        return j.record("duplicates", "retry", {"same": [1, "é"]})
    with ThreadPoolExecutor(max_workers=12) as pool:
        results = list(pool.map(duplicate, range(12)))
    require(all(r.returncode == 0 for r in results), [r.stderr for r in results if r.returncode])
    duplicate_events = j.chain("duplicates", 1)
    require(duplicate_events[0]["event_id"] == "retry" and
            duplicate_events[0]["requested"] == {"same": [1, "é"]},
            "duplicate identity or caller payload changed")
    before = snapshot(j.events("duplicates"))
    require(j.record("duplicates", "retry", {"same": [1, "é"]}).returncode == 0,
            "identical retry rejected")
    require(snapshot(j.events("duplicates")) == before, "identical retry changed bytes")
    j.rejected(j.record("duplicates", "retry", {"same": False}), "conflict")
    require(snapshot(j.events("duplicates")) == before, "conflict changed event bytes")
    for extra in [["--observed", '{"changed":true}'], ["--evidence", "new-evidence"],
                  ["--type", "different"]]:
        result = j.call("record", "--run-id", "duplicates", "--event-id", "retry",
                        "--type", "probe", "--requested", '{"same":[1,"é"]}', *extra)
        j.rejected(result, "conflict")
        require(snapshot(j.events("duplicates")) == before, "caller-content conflict changed bytes")
    # Idempotence precedes the already-open guard, but only for matching content.
    route = j.root / "route.json"
    route.write_text('{}\n')
    args = ["open", "--run-id", "opened", "--route", str(route), "--event-id", "open-id"]
    require(j.call(*args).returncode == 0, "open failed")
    require(j.call(*args).returncode == 0, "identical open retry failed")
    j.rejected(j.call("open", "--run-id", "opened", "--route", str(route)), "already opened")
    j.chain("opened", 1)
    print("synchronized 24 distinct + 12 duplicate writers: %.2fs" % (time.monotonic() - started))


def unknown(j):
    before = snapshot(j.root)
    result = subprocess.run(j.dispatcher + ["status", "--run-id", "absent", "--json"],
                            cwd=j.root, env=j.env, capture_output=True, text=True, timeout=10)
    j.rejected(result, "unknown")
    require(snapshot(j.root) == before, "unknown read mutated project or home")


def corruption(j):
    # Immutable fixtures were captured from the pre-fix v1 writer; no new writer
    # is used to construct the valid control or derive expected hash values.
    fixture = json.loads((FIXTURES / "legacy.json").read_text())
    controls = FIXTURES / "canonical.json"
    for control in json.loads(controls.read_text()):
        actual = canonical(control["payload"])
        require(actual.decode() == control["canonical"], ("canonical bytes", control["name"]))
        require(hashlib.sha256(actual).hexdigest() == control["sha256"], control["name"])
    mutations = json.loads((FIXTURES / "invalid.json").read_text())
    complex_events = json.loads((FIXTURES / "legacy-complex.json").read_text())
    complex_path = j.events("legacy-complex")
    complex_path.mkdir(parents=True)
    for index, event in enumerate(complex_events, 1):
        (complex_path / (str(index) + ".json")).write_text(json.dumps(event, ensure_ascii=False) + "\n")
    complex_before = snapshot(complex_path)
    require(j.call("status", "--run-id", "legacy-complex", "--json").returncode == 0,
            "legacy numeric/Unicode/escape history rejected")
    require(j.record("legacy-complex", "next").returncode == 0, "complex legacy append failed")
    require(all((complex_path / name).read_bytes() == data for name, data in complex_before.items()),
            "complex legacy append changed original bytes")
    j.chain("legacy-complex", 3)
    path = j.events("legacy")
    path.mkdir(parents=True)
    for index, event in enumerate(fixture, 1):
        (path / (str(index) + ".json")).write_text(json.dumps(event) + "\n")
    before = snapshot(path)
    result = j.call("status", "--run-id", "legacy", "--json")
    require(result.returncode == 0 and json.loads(result.stdout)["events"] == 2, result.stderr)
    require(snapshot(path) == before, "legacy inspection rewrote bytes")
    for mutation in mutations:
        name = mutation["name"]
        # Restore exactly the same valid run before introducing ONE defect.
        for filename, content in before.items():
            (path / filename).write_bytes(content)
        target = path / "2.json"
        event = json.loads(target.read_text())
        if "raw" in mutation:
            target.write_text(mutation["raw"])
        else:
            event.update(mutation["replace"])
            if mutation.get("reseal", True):
                seal(event)
            target.write_text(json.dumps(event) + "\n")
        damaged = snapshot(path)
        j.rejected(j.call("status", "--run-id", "legacy", "--json"))
        j.rejected(j.record("legacy", "new"))
        require(snapshot(path) == damaged, (name, "invalid history mutated"))
    for filename, content in before.items():
        (path / filename).write_bytes(content)
    require(j.record("legacy", "new").returncode == 0, "valid legacy append rejected")
    require(all((path / name).read_bytes() == data for name, data in before.items()),
            "append rewrote original legacy events")
    j.chain("legacy", 3)
    publication_failures(j)


def publication_failures(j):
    # Tool failure is an interrupted construction, never an accepted event.
    # Include plausible stdout plus nonzero status, and invalid stdout with zero
    # status, so an empty-output check alone cannot satisfy this contract.
    cases = [
        ("hash-exit", "sha256sum", "exit 44\n"),
        ("hash-output-exit", "sha256sum", "printf '%s  -\\n' '" + "a" * 64 + "'\nexit 44\n"),
        ("hash-invalid", "sha256sum", "printf 'not-a-digest  -\\n'\n"),
        ("clock-exit", "date", "printf '2026-01-01T00:00:00Z\\n'\nexit 44\n"),
        ("identity-query-exit", "jq", """case "$*" in
  *'any(.[]; .event_id == $id)'*) exit 44 ;;
  *) exec """ + '"' + shutil.which("jq") + '" "$@" ;;\nesac\n'),
    ]
    for name, tool, body in cases:
        shim = j.root / ("fault-" + name)
        shim.mkdir()
        (shim / tool).write_text("#!/bin/sh\n" + body)
        (shim / tool).chmod(0o755)
        env = dict(j.env, PATH=str(shim) + os.pathsep + j.env["PATH"])
        j.rejected(j.record(name, env=env))
        require(not list(j.events(name).glob("*.json")), (name, "failed construction published"))
        require(not j.lock(name).exists(), (name, "failed construction stranded owned lock"))
        require(j.record(name).returncode == 0, (name, "clean retry failed"))
        j.chain(name, 1)
        if tool == "sha256sum":
            before = snapshot(j.events(name))
            j.rejected(j.record(name, env=env))
            require(snapshot(j.events(name)) == before, (name, "hash failure changed existing prefix"))
            require(j.record(name).returncode == 0, (name, "retry after prefix validation failure failed"))
            j.chain(name, 2)
    print("failed hash/clock/identity-query construction rejected; clean retries passed")


def wait_for(path, process, timeout=10):
    deadline = time.monotonic() + timeout
    while not path.exists():
        require(process.poll() is None, ("writer exited before barrier", process.returncode))
        require(time.monotonic() < deadline, ("barrier timed out", str(path)))
        time.sleep(.02)


def interruption(j):
    # Ownership metadata is diagnostic, never authority to steal. Include live,
    # apparently-dead, reused (our own), unknown, and absent owner identities.
    for index, metadata in enumerate([None, "", "pid=999999999\ntoken=old\n",
                                       "pid=%s\ntoken=foreign\n" % os.getpid(),
                                       "not-owner-metadata\n"]):
        run = "stale-%s" % index
        require(j.record(run).returncode == 0, "seed failed")
        lock = j.lock(run)
        lock.mkdir()
        if metadata is not None:
            (lock / "owner").write_text(metadata)
        before = snapshot(j.events(run).parent)
        env = dict(j.env, EIDOLONS_LEDGER_LOCK_TIMEOUT="1")
        started = time.monotonic()
        j.rejected(j.record(run, env=env), "recovery-required")
        require(time.monotonic() - started < 5, "unbounded ownership wait")
        j.rejected(j.call("status", "--run-id", run, "--json"), "recovery-required")
        require(snapshot(j.events(run).parent) == before, "stale ownership stolen or changed")
    for value in ["0", "-1", "nan", "1.5", "99999999999999999999999"]:
        j.rejected(j.record("invalid-budget", env=dict(j.env, EIDOLONS_LEDGER_LOCK_TIMEOUT=value)))
    # PATH shims are real delayed subprocesses, not product fault-injection hooks.
    # SIGKILL the owner while mv survives: no successor may enter until proven
    # quiescence and explicit operator recovery (which this test does not do).
    for phase, sig in [("before", signal.SIGKILL), ("after", signal.SIGKILL),
                       ("before", signal.SIGTERM), ("metadata", signal.SIGKILL),
                       ("cleanup", signal.SIGKILL)]:
        run = "%s-%s" % (phase, sig)
        require(j.record(run).returncode == 0, "seed failed")
        first = (j.events(run) / "1.json").read_bytes()
        shim = j.root / ("shim-" + run)
        shim.mkdir()
        marker = shim / "entered"
        release = shim / "release"
        done = shim / "done"
        command = "mkdir" if phase == "metadata" else "rm" if phase == "cleanup" else "mv"
        real = shutil.which(command)
        # The condition isolates the operation owning/publicizing ledger state.
        condition = '*".append-lock"*' if command == "mkdir" else '*"/owner"*' if command == "rm" else '*"/2.json"*'
        script = '#!/usr/bin/env bash\nset -eu\ncase "$*" in\n  ' + condition + ')\n'
        if phase in ("after", "metadata"):
            script += '    "' + real + '" "$@"\n'
        script += '    printf "%s\\n" "$$" > "' + str(marker) + '"\n'
        script += '    while [ ! -e "' + str(release) + '" ]; do sleep 0.02; done\n'
        if phase not in ("after", "metadata"):
            script += '    "' + real + '" "$@"\n'
        script += '    : > "' + str(done) + '"\n    ;;\n  *) "' + real + '" "$@" ;;\nesac\n'
        (shim / command).write_text(script)
        (shim / command).chmod(0o755)
        env = dict(j.env, PATH=str(shim) + os.pathsep + j.env["PATH"])
        process = subprocess.Popen(j.command + ["record", "--run-id", run, "--type", "probe"],
                                   cwd=j.root, env=env, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
        try:
            wait_for(marker, process)
            process.send_signal(sig)
            time.sleep(.1)
            require(j.lock(run).is_dir(), (phase, "lock released before child quiescence"))
            blocked = dict(j.env, EIDOLONS_LEDGER_LOCK_TIMEOUT="1")
            j.rejected(j.record(run, env=blocked), "recovery-required")
            j.rejected(j.call("status", "--run-id", run, "--json"), "recovery-required")
        finally:
            release.touch()
            process.wait(timeout=10)
        deadline = time.monotonic() + 10
        while not done.exists() and time.monotonic() < deadline:
            time.sleep(.02)
        require(done.exists(), (phase, "delayed child never completed"))
        require((j.events(run) / "1.json").read_bytes() == first, "published prefix changed")
        if phase in ("before", "after", "cleanup"):
            j.chain(run, 2)
        if sig == signal.SIGKILL:
            require(j.lock(run).is_dir(), (phase, "dead owner lock was released"))
            j.rejected(j.record(run, env=blocked), "recovery-required")
        else:
            require(process.returncode != 0, "interrupted writer reported success")
            require(not j.lock(run).exists(), "owned TERM cleanup did not complete")
            require(j.record(run).returncode == 0, "TERM cleanup prevented next writer")
    print("ownership, delayed publisher, metadata and cleanup interruption gates passed")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="journal-conformance-") as directory:
        globals()[sys.argv[1]](Journal(Path(directory)))
