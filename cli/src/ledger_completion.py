#!/usr/bin/env python3
"""Completion observations and pure projection; journal publication stays in Bash.

Production supplies no authenticated contexts. A serialized claim, hash, label,
reporter UUID or historical view can never manufacture that separate authority.
"""
import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import uuid


class Invalid(ValueError):
    pass


def canonical(value):
    # New snapshot/projection format only. Legacy event digests remain jq -cS+LF.
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True,
                       allow_nan=False) + "\n").encode("utf-8")


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def file_digest(path):
    with open(path, "rb") as stream:
        before = os.fstat(stream.fileno())
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(65536), b""):
            result.update(block)
        after = os.fstat(stream.fileno())
    if (before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != \
       (after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns):
        raise Invalid("input changed while being read")
    return result.hexdigest()


def git(*args):
    result = subprocess.run(["git"] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"))
    if result.returncode:
        raise Invalid("candidate capture requires a readable Git worktree and valid integration base")
    return result.stdout.decode("utf-8")


def relative_input(value, root):
    if not isinstance(value, str) or not value:
        raise Invalid("candidate input paths must be nonempty strings")
    path = Path(value)
    if path.is_absolute():
        try:
            path = path.relative_to(root)
        except ValueError:
            raise Invalid("candidate input must be inside the Git worktree")
    if ".." in path.parts or str(path) == ".":
        raise Invalid("candidate input must be a non-traversing file path")
    name = path.as_posix()
    if name == ".git" or name.startswith(".git/") or name == ".eidolons/.ledger" or name.startswith(".eidolons/.ledger/"):
        raise Invalid("tracked or required input overlaps fixed operational state")
    return name


def resolution_metadata(name, root):
    """Bind directory permissions and every symlink traversed to reach an input."""
    current = root
    pending = list(Path(name).parts)
    metadata = [{"path": ".", "mode": stat.S_IMODE(root.stat().st_mode), "kind": "directory"}]
    links = 0
    while pending:
        part = pending.pop(0)
        if part == "..":
            if current == root:
                raise Invalid("external symlink input is unsupported: " + name)
            current = current.parent
            continue
        path = current / part
        info = path.lstat()
        item = {"path": path.relative_to(root).as_posix(), "mode": stat.S_IMODE(info.st_mode)}
        if stat.S_ISLNK(info.st_mode):
            links += 1
            if links > 40:
                raise Invalid("symlink resolution limit exceeded: " + name)
            target = os.readlink(path)
            item.update(kind="symlink", target=target)
            target_path = Path(target)
            if target_path.is_absolute():
                try:
                    target_path = target_path.relative_to(root)
                except ValueError:
                    raise Invalid("external symlink input is unsupported: " + name)
                current = root
            pending = list(target_path.parts) + pending
        else:
            item["kind"] = "directory" if stat.S_ISDIR(info.st_mode) else "file" if stat.S_ISREG(info.st_mode) else "other"
            current = path
        metadata.append(item)
    return metadata


def entry(name, root):
    path = root / name
    info = path.lstat()
    base = {"path": name, "mode": stat.S_IMODE(info.st_mode),
            "resolution": resolution_metadata(name, root)}
    # Resolve ancestors too: an ordinary-looking file under an external symlink
    # is just as ineligible as an external final-component symlink.
    resolved = path.resolve(strict=True)
    try:
        target = resolved.relative_to(root).as_posix()
    except ValueError:
        raise Invalid("external symlink input is unsupported: " + name)
    relative_input(target, root)
    if stat.S_ISLNK(info.st_mode):
        if not resolved.is_file():
            raise Invalid("non-file symlink input is unsupported: " + name)
        return dict(base, kind="symlink", target=os.readlink(path), resolved_target=target,
                    target_mode=stat.S_IMODE(resolved.stat().st_mode), sha256=file_digest(resolved))
    if not stat.S_ISREG(info.st_mode):
        raise Invalid("non-file candidate input is unsupported: " + name)
    return dict(base, kind="file", sha256=file_digest(path))


def string_list(value, label):
    if not isinstance(value, list) or any(not isinstance(x, str) or not x for x in value) or len(set(value)) != len(value):
        raise Invalid(label + " must contain distinct nonempty strings")
    return value


def snapshot(criteria_path, integration_base):
    root = Path(git("rev-parse", "--show-toplevel").strip()).resolve()
    if root != Path.cwd().resolve():
        raise Invalid("run candidate capture/status from the Git worktree root")
    criteria_name = relative_input(criteria_path, root)
    # Validate containment before opening potentially symlinked definitions.
    criteria_entry = entry(criteria_name, root)
    criteria = json.loads((root / criteria_name).read_text())
    if not isinstance(criteria, dict) or criteria.get("schema_version") != "1.0":
        raise Invalid("criteria require schema_version 1.0")
    if any(key in criteria for key in ("exclude", "excludes", "exclusions", "ignore")):
        raise Invalid("user-defined candidate exclusions are unsupported")
    required = criteria.get("required_checks")
    if not isinstance(required, list) or not required:
        raise Invalid("criteria require a nonempty mandatory check set")
    for check in required:
        if not isinstance(check, dict) or set(check) != {"id", "oracle_id"} or any(not isinstance(check[k], str) or not check[k] for k in check):
            raise Invalid("required checks need id and oracle_id")
    if len({c["id"] for c in required}) != len(required):
        raise Invalid("duplicate mandatory check ID")
    untracked = string_list(criteria.get("required_untracked", []), "required_untracked")
    environment = string_list(criteria.get("environment", []), "environment")
    configuration = string_list(criteria.get("configuration", []), "configuration")
    tracked = set(filter(None, git("ls-files", "--cached", "-z").split("\0")))
    discovered = set(filter(None, git("ls-files", "--others", "--exclude-standard", "-z").split("\0")))
    explicit = {relative_input(p, root) for p in untracked + configuration + [criteria_name]}
    for name in tracked | explicit:
        relative_input(name, root)
    discovered = {p for p in discovered if not (p == ".eidolons/.ledger" or p.startswith(".eidolons/.ledger/"))}
    files = [entry(name, root) for name in sorted(tracked | discovered | explicit)]
    env = {}
    for name in environment:
        if name not in os.environ:
            raise Invalid("required environment variable is absent: " + name)
        env[name] = hashlib.sha256(os.environ[name].encode()).hexdigest()
    config = [entry(relative_input(name, root), root) for name in configuration]
    base = git("rev-parse", "--verify", integration_base + "^{commit}").strip()
    body = {"files": files, "head": git("rev-parse", "HEAD").strip(), "integration_base": base,
            "criteria_digest": criteria_entry["sha256"], "environment": env, "configuration": config,
            "required_checks": required, "inputs": {"criteria": criteria_name, "integration_base": integration_base}}
    identity = {"candidate": digest(body), "criteria": body["criteria_digest"],
                "environment": digest(env), "configuration": digest(config), "integration_base": base}
    return dict(body, identity=identity)


@dataclass(frozen=True)
class AuthenticatedContext:
    """Already-authenticated input to the pure evaluator, never a wire object.

    V4-05's only producer is its test harness. No CLI path constructs instances.
    A future qualified runner must establish actual invocation/context access.
    """
    maker_invocation_id: str
    checker_invocation_id: str
    context_access: str


def qualified(observation, context):
    return (isinstance(context, AuthenticatedContext) and context.context_access == "qualified" and
            bool(context.maker_invocation_id) and bool(context.checker_invocation_id) and
            context.maker_invocation_id != context.checker_invocation_id and
            observation.get("maker_invocation_id") == context.maker_invocation_id and
            observation.get("checker_invocation_id") == context.checker_invocation_id)


def project(candidate, observations, current_identity, evidence, authenticated=None):
    """Deterministic evaluator. Invocation IDs are provenance, not grouping keys."""
    authenticated = authenticated or {}
    reasons = []
    checks = []
    required = candidate.get("required_checks", []) if isinstance(candidate, dict) else []
    identity = candidate.get("identity") if isinstance(candidate, dict) else None
    current = bool(identity) and identity == current_identity
    if not current:
        reasons.append("candidate-unavailable-or-stale")
    if not required:
        reasons.append("mandatory-check-set-empty")
    for requirement in required:
        relevant = [o for o in observations if o.get("identity") == identity and
                    o.get("check_id") == requirement["id"] and o.get("oracle_id") == requirement["oracle_id"]]
        latest = max(relevant, key=lambda o: o["sequence"]) if relevant else None
        outcome = latest.get("outcome", "unknown") if latest else "missing"
        event_id = latest["event_id"] if latest else None
        integrity = evidence.get(event_id, "unavailable") if latest else "unavailable"
        provenance = ("authenticated-independent" if latest and qualified(latest, authenticated.get(event_id))
                      else "self-attested" if latest else "unavailable")
        checks.append({"id": requirement["id"], "oracle_id": requirement["oracle_id"], "event_id": event_id,
                       "outcome": outcome, "artifact_integrity": integrity, "execution_provenance": provenance})
        if outcome != "pass":
            reasons.append(requirement["id"] + ":" + outcome)
        if integrity != "verified":
            reasons.append(requirement["id"] + ":evidence-" + integrity)
        if provenance != "authenticated-independent":
            reasons.append(requirement["id"] + ":unqualified-provenance")
    integrity_values = [c["artifact_integrity"] for c in checks]
    integrity = next((x for x in ("missing", "changed", "unavailable") if x in integrity_values),
                     "verified" if integrity_values else "unavailable")
    provenance = ("authenticated-independent" if checks and all(c["execution_provenance"] == "authenticated-independent" for c in checks)
                  else "self-attested" if any(c["event_id"] for c in checks) else "unavailable")
    return {"candidate_status": {"status": "current" if current else "stale" if identity else "unavailable"},
            "checks": checks, "artifact_integrity": {"status": integrity},
            "execution_provenance": {"status": provenance},
            "acceptance_status": {"status": "accepted" if not reasons else "not-accepted", "reasons": reasons}}


def evidence_status(refs):
    if not isinstance(refs, list) or not refs:
        return "unavailable"
    result = "verified"
    for ref in refs:
        if not isinstance(ref, dict) or not isinstance(ref.get("ref"), str) or not isinstance(ref.get("digest"), str):
            return "unavailable"
        try:
            actual = file_digest(ref["ref"])
        except (OSError, Invalid):
            return "missing"
        if actual != ref["digest"]:
            result = "changed"
    return result


def candidate_event(history, event_id=None):
    events = [e for e in history if e["event_type"] == "candidate-captured" and
              e["observed"].get("kind") == "candidate" and (event_id is None or e["event_id"] == event_id)]
    if not events:
        return None
    result = events[-1]
    if result["observed"].get("contract_version") != "1.0" or not isinstance(result["observed"].get("snapshot"), dict):
        raise Invalid("unsupported or invalid candidate observation")
    return result


def current_inputs(history):
    captured = candidate_event(history)
    candidate = captured["observed"]["snapshot"] if captured else None
    current_identity = None
    errors = []
    if candidate:
        try:
            source = candidate["inputs"]
            current_identity = snapshot(source["criteria"], source["integration_base"])["identity"]
        except (OSError, ValueError, RuntimeError, KeyError) as exc:
            errors.append(str(exc))
    observations = []
    evidence = {}
    for event in history:
        observed = event["observed"]
        if event["event_type"] != "completion-check" or observed.get("kind") != "check":
            continue
        if observed.get("contract_version") != "1.0":
            raise Invalid("unsupported completion observation")
        observation = dict(observed, sequence=event["sequence"], event_id=event["event_id"])
        observations.append(observation)
        evidence[event["event_id"]] = evidence_status(observed.get("evidence_refs"))
    return {"candidate": candidate, "observations": observations, "current_identity": current_identity,
            "evidence": evidence, "validation_errors": errors}


def evaluate_inputs(inputs):
    # Deliberately no wire-level authenticated/trusted argument, even if the
    # supplied serialized object has such extra keys.
    result = project(inputs["candidate"], inputs["observations"], inputs["current_identity"], inputs["evidence"])
    result["validation_errors"] = inputs.get("validation_errors", [])
    if result["validation_errors"] and result["acceptance_status"]["status"] == "accepted":
        result["acceptance_status"] = {"status": "not-accepted", "reasons": ["revalidation-failed"]}
    return result


def status(history):
    inputs = current_inputs(history)
    result = evaluate_inputs(inputs)
    plans = [e for e in history if e["event_type"] == "planned"]
    dispatch = [e["observed"]["dispatch"] for e in history if e["observed"].get("dispatch") is not None]
    legacy = [e for e in history if e["event_type"] == "checked"]
    if legacy and not result["checks"]:
        observed = legacy[-1]["observed"]
        refs = [{"ref": r["ref"], "digest": observed.get("artifact_digest")} for r in legacy[-1]["evidence_refs"] if isinstance(r, dict) and "ref" in r]
        result["artifact_integrity"] = {"status": evidence_status(refs)}
        result["execution_provenance"] = {"status": "self-attested"}
    result.update(run_id=history[0]["run_id"], events=len(history), requested=plans[0]["requested"] if plans else {},
                  dispatch=dispatch[-1] if dispatch else "unobserved", completion="not-complete",
                  reconciliation_required=any(e["observed"].get("side_effect") == "unknown" for e in history),
                  historical=False, execution_terminations=[{"event_id":e["event_id"], "transport":e["event_type"], "state":"terminated"}
                    for e in history if e["event_type"] in ("native-completed", "a2a-completed", "mcp-result")])
    return result


def prepare(history, action, request):
    refs = []
    if action == "candidate":
        observed = {"kind":"candidate", "contract_version":"1.0",
                    "snapshot":snapshot(request["criteria"], request["integration_base"])}
    elif action == "complete":
        event = candidate_event(history, request["candidate_event_id"])
        if not event:
            raise Invalid("unknown candidate capture")
        captured = event["observed"]["snapshot"]
        source = captured["inputs"]
        current = snapshot(source["criteria"], source["integration_base"])
        if current["identity"] != captured["identity"]:
            raise Invalid("candidate is stale; capture the current candidate before reporting a check")
        check = next((c for c in captured["required_checks"] if c["id"] == request["check_id"]), None)
        if not check:
            raise Invalid("check ID is not in the candidate mandatory set")
        if request["artifact"] and Path(request["artifact"]).is_file():
            artifact = str(Path(request["artifact"]).resolve(strict=True))
            refs = [{"kind":"artifact", "ref":artifact, "digest":file_digest(artifact)}]
        elif request["verdict"] == "pass":
            raise Invalid("passing completion requires an existing artifact")
        # A failed/cancelled check can terminate before producing its artifact.
        # Preserve that latest outcome, with unavailable integrity, not an older pass.
        observed = {"kind":"check", "contract_version":"1.0", "identity":captured["identity"],
                    "check_id":check["id"], "oracle_id":check["oracle_id"], "outcome":request["verdict"],
                    "checker_label":request["checker"], "scope":request["scope"], "evidence_refs":refs,
                    "maker_invocation_id":None, "checker_invocation_id":None}
    elif action == "capture":
        observed = {"kind":"projection", "contract_version":"1.0", "inputs":current_inputs(history)}
    else:
        raise Invalid("unknown typed capture")
    return {"requested":request, "observed":observed, "evidence_refs":refs}


def historical_view(event):
    observed = event.get("observed", {})
    if observed.get("kind") != "projection" or observed.get("contract_version") != "1.0":
        raise Invalid("reference is not a canonical captured projection")
    result = evaluate_inputs(observed["inputs"])
    result.update(historical=True, captured_at=event["timestamp"], capture_event_id=event["event_id"],
                  capture_invocation_id=observed["capture"]["invocation_id"])
    return result


def render(value, fmt):
    if fmt == "json":
        return json.dumps(value, sort_keys=True, ensure_ascii=True, indent=2) + "\n"
    lines = [("Historical evidence" if value.get("historical") else "Current evidence"),
             "Artifact integrity: " + value["artifact_integrity"]["status"],
             "Execution provenance: " + value["execution_provenance"]["status"],
             "Acceptance: " + value["acceptance_status"]["status"]]
    if value.get("historical"):
        lines += ["Captured at: " + value["captured_at"], "Capture: " + value["capture_event_id"],
                  "Reporter invocation: " + value["capture_invocation_id"], "Historical only; not current acceptance."]
    for check in value["checks"]:
        lines.append(check["id"] + ": " + check["outcome"])
    lines.extend("Revalidation: " + error for error in value.get("validation_errors", []))
    if fmt == "markdown":
        return "# " + lines[0] + "\n\n" + "\n".join("- " + line for line in lines[1:]) + "\n"
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["prepare", "decorate", "status", "render", "reference"])
    parser.add_argument("--kind")
    parser.add_argument("--request")
    parser.add_argument("--timestamp")
    parser.add_argument("--event-id")
    parser.add_argument("--file")
    parser.add_argument("--format", choices=["json", "text", "markdown"], default="json")
    parser.add_argument("--compare")
    args = parser.parse_args()
    if args.action == "reference":
        obj = json.loads(Path(args.file).read_text())
        if not isinstance(obj, dict) or set(obj) != {"schema_version", "kind", "run_id", "event_id"} or obj.get("schema_version") != "1.0" or obj.get("kind") != "completion-view-reference" or any(not isinstance(obj[k], str) or not obj[k] for k in obj):
            raise Invalid("canonical capture reference required; create a ledger capture, then reference its run_id and event_id (legacy observation arrays are unsupported)")
        print(json.dumps(obj))
        return
    data = json.load(sys.stdin)
    if args.action == "prepare":
        value = prepare(data, args.kind, json.loads(args.request))
    elif args.action == "decorate":
        value = dict(data, capture={"invocation_id":str(uuid.uuid4()), "captured_at":args.timestamp})
    elif args.action == "status":
        value = status(data)
    else:
        event = next((e for e in data if e["event_id"] == args.event_id), None)
        if not event:
            raise Invalid("unknown canonical capture reference")
        value = historical_view(event)
    output = render(value, args.format) if args.action in ("status", "render") else json.dumps(value) + "\n"
    if args.compare and Path(args.compare).read_text() != output:
        raise Invalid("generated evidence view drift: bytes differ from canonical capture")
    sys.stdout.write(output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as exc:
        print("completion: " + str(exc), file=sys.stderr)
        sys.exit(1)
