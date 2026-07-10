---
name: bump-mcp
description: Pin an MCP server to a new version in the nexus catalogue (roster/mcps.yaml). Use when the user says "bump <mcp> to vX.Y.Z", "pin atlas-aci to 2.0.0", "crystalium shipped a release", "update the MCP catalogue", or after releasing an MCP server upstream. Covers digest capture and verification, backfilling skipped releases, the mcp_images.bats fixture coupling, CHANGELOG, the ESL change, and the verification gates. This is the MCP counterpart to `add-eidolon`, which covers Eidolons in roster/index.yaml — do not confuse the two.
---

# bump-mcp — Pin an MCP server to a new version in the nexus catalogue

`roster/mcps.yaml` is the closed catalogue of the five nexus MCPs (`atlas-aci`, `junction`, `crystalium`, `tonberry`, `atomos`). Under the default `integrity.enforcement: strict` posture it is **what `eidolons verify` checks an installed image against** — so a stale pin is not cosmetic. It means every consumer installs an old image and cannot reach newer versions with `eidolons mcp use <name>@<ver>`.

`add-eidolon` handles **Eidolons** (`roster/index.yaml`). This skill handles **MCP servers** (`roster/mcps.yaml`). They are different files with different shapes.

## Invariants you must respect

1. **Never copy a digest from a release note.** Resolve every digest from the registry yourself. A wrong digest breaks `eidolons verify` for every consumer under `strict`.
2. **Git tags are `v`-prefixed; image tags usually are not.** `git tag v2.0.0` but `ghcr.io/rynaro/atlas-aci:2.0.0`. `imagetools inspect …:v2.0.0` will silently return nothing. Check both.
3. **Backfill releases the catalogue skipped.** If `releases:` jumps from `0.2.3` to the new version, every intermediate release is unreachable via `mcp use`. Record them, with digests resolved from the registry.
4. **`catalogue_version` is for the file's *shape*, not its contents.** Adding releases does not bump it. Adding a new *field* does.
5. **Bump `updated_at`.**
6. **Do not sweep unrelated working-tree changes into the commit.** This repo's tree frequently carries uncommitted `.mcp.json` / `.gitignore` edits. `git add` the exact paths.

## Phase 0 — Confirm the upstream release is real

```bash
gh release view v<VER> --repo <owner>/<repo> --json tagName,isDraft,publishedAt
```

For `kind: oci-image` MCPs, confirm the image exists and is a multi-arch index:

```bash
docker buildx imagetools inspect ghcr.io/rynaro/<name>:<VER> --raw \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["mediaType"], len(d.get("manifests",[])), "platforms")'
```

If the release workflow signs with cosign and attests SBOM/provenance, say so in the CHANGELOG — it is why the digest can be trusted.

## Phase A — Capture and verify every digest

Not just the new one. Every version you will record.

```bash
for t in 0.3.0 0.3.1 0.4.0 2.0.0; do
  printf '%-8s %s\n' "$t" \
    "$(docker buildx imagetools inspect ghcr.io/rynaro/<name>:$t --format '{{.Manifest.Digest}}')"
done
```

Release dates: `gh release view v<VER> --json publishedAt`. Some tags have an image but **no GitHub Release object** — fall back to the git tag date (`git log -1 --format=%aI <tag>`) and say which you used.

## Phase B — Edit `roster/mcps.yaml`

Under the MCP's `versions:` block:

- `latest:` → the new version
- `pins.stable:` → the new version
- `releases:` → add every version with `digest:` and `released_at:`
- top-of-file `updated_at:` → today

If you are backfilling, leave a comment saying *why* the catalogue skipped them. A future reader will want to know it was an oversight, not a policy.

Then **re-verify what you wrote against the registry**, reading the digests back out of the file rather than out of your own scrollback:

```bash
python3 - <<'PY' > /tmp/dg.txt
import yaml
d = yaml.safe_load(open('roster/mcps.yaml'))
e = [m for m in d['mcps'] if m['name'] == '<name>'][0]
for v, r in sorted(e['versions']['releases'].items()):
    print(v, r['digest'])
PY
while read -r v dg; do
  real=$(docker buildx imagetools inspect "ghcr.io/rynaro/<name>:$v" --format '{{.Manifest.Digest}}' 2>/dev/null)
  [ "$real" = "$dg" ] && echo "$v OK" || echo "$v MISMATCH recorded=$dg real=$real"
done < /tmp/dg.txt
```

## Phase C — The test fixture is coupled to `pins.stable`

**This is the trap.** `cli/tests/mcp_images.bats` hardcodes the stable digest:

```bash
ATLAS_ACI_PINNED="sha256:…"
```

and `S8` asserts *"image present at the stable digest ⇒ `DRIFT=no`"*. If you bump the catalogue and forget the fixture, **`S8` keeps passing — vacuously.** It asserts no-drift against a digest nothing pins any more. The hardcoded constant is a *proxy* for "the catalogue's stable digest".

Bump the fixture, and make sure a guard derives the value instead of trusting it. `S8-guard` does this today for `atlas-aci` (pure `awk`, bash 3.2 safe). If you add a fixture for another MCP, add its guard too.

Prove the guard has teeth before you trust it:

```bash
# revert the fixture to the OLD digest -> S8-guard and S8 must BOTH fail
bats cli/tests/mcp_images.bats | grep '^not ok'
# restore -> both pass
```

Note `CRYSTALIUM_PINNED` is deliberately a *non-matching* digest — `S9` exercises the `DRIFT=yes` path. Do not "fix" it.

## Phase D — CHANGELOG

Add to `## [Unreleased]` under `### Changed`. The house style is a dense paragraph, not a bullet fragment: what moved, the digest, why it matters, what breaks for consumers.

**Link to an immutable ref.** If you link to an upstream artefact under `.spectra/changes/<id>/`, link to the **tag**, not `blob/main` — the ESL lifecycle archives that folder to `.spectra/changes/archive/<date>-<id>/` and `blob/main` will 404:

```
https://github.com/<owner>/<repo>/blob/v2.0.0/.spectra/changes/<id>/RETRO.md   ✅
https://github.com/<owner>/<repo>/blob/main/.spectra/changes/<id>/RETRO.md     ❌ breaks on archive
```

State breaking changes plainly. For a schema-epoch bump: *"the on-disk DB is derived data with no in-place migration — re-index once."*

## Phase E — ESL change

This repo runs ESL. Open a change before editing (`trivial` routes need no spec):

```bash
tb() { docker run --rm -i --user "$(id -u):$(id -g)" \
  -v "$PWD:/workspace:z" -w /workspace --cap-drop ALL --security-opt no-new-privileges \
  ghcr.io/rynaro/tonberry@sha256:<pinned> "$@"; }

tb propose --change_id mcp-<name>-<ver-dashed> --maker vivi --checker kupo \
   --has_code true --spec_ref spec.md --project_root /workspace
tb right_size --change_id … --files_touched 5 --rubric_score 3 --tradeoff_present false --project_root /workspace
```

`has_code: true` — you are editing `cli/tests/*.bats`. Write `spec.md`, thread `acceptance_checks` via `compose_manifest --patch`, then `transition`. A catalogue bump right-sizes to `lite`.

## Phase F — Verification

```bash
make schema                       # jq + yq structural checks CI runs
EIDOLONS_NEXUS="$(pwd)" bash cli/eidolons mcp show <name>    # CLI reads the catalogue
make test                         # parallel; needs GNU `parallel`
bats cli/tests/                   # sequential fallback (~2m30s) when `parallel` is absent
```

**Before blaming your change for a red test, check whether it is red on a clean tree.** Stash and re-run the single file:

```bash
git stash push -q roster/mcps.yaml cli/tests/mcp_images.bats
bats cli/tests/<file>.bats | grep '^not ok'
git stash pop -q
```

At time of writing, `cli/tests/doctor_deep.bats` `DD-7` fails on a clean tree. Say so in the PR rather than silently accepting a red suite.

## Phase G — Branch, commit, PR

Branch `fix/mcp-<name>-<version-dashed>` (mirrors the `fix/roster-<eidolon>-<version>` convention). Stage exact paths. Never push to `main` directly. Open a PR; do not merge without the user's word.

## Traps, learned the hard way

- **`imagetools inspect ghcr.io/x:v2.0.0` returns nothing** while `:2.0.0` works. The `v` is a git convention, not a registry one.
- **A hardcoded digest in a test is a proxy.** Derive it from the catalogue or a bump will make the test pass vacuously.
- **`blob/main` links to ESL change folders rot** the moment the change is archived.
- **The catalogue can silently skip releases for months.** Check `releases:` against `gh release list` before you assume you are bumping by one.
- **The local wiring (`.mcp.json`, `eidolons.mcp.lock`) is separate from the catalogue.** Those are consumer artefacts, often untracked or carrying unrelated edits. Update them with `eidolons mcp upgrade <name>`, in their own commit, or not at all.
