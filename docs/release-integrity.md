# Release Integrity

Eidolons uses independent SemVer releases for the nexus, EIIS, and every
Eidolon repo. Runtime install safety is anchored by exact Git tags plus
roster-published target metadata, not by floating branches.

## Release Metadata

Roster entries may publish integrity metadata under
`versions.releases.<version>`:

```yaml
versions:
  latest: "1.0.5"
  pins:
    stable: "1.0.5"
  releases:
    "1.0.5":
      tag: "v1.0.5"
      commit: "<40-char commit>"
      tree: "<40-char tree>"
      archive_sha256: "<64-char sha256>"
      manifest_sha256: null
      provenance:
        github_attestation: true
        workflow: ".github/workflows/release.yml"
```

When metadata exists, `eidolons sync` and `eidolons upgrade` must clone the
matching `vX.Y.Z` tag and verify the resolved commit/tree/checksum before any
per-Eidolon `install.sh` runs. A mismatch aborts the install.

Existing roster entries without release metadata are still accepted while
`integrity.enforcement: warn`. They emit a warning and write
`verification: "legacy-warning"` into `eidolons.lock`. A future registry bump
can switch enforcement to `strict`, at which point missing metadata becomes a
hard failure.

## Lockfile Fields

`eidolons.lock` records the resolved commit and integrity status for every
installed member:

```yaml
members:
  - name: atlas
    version: "1.0.5"
    resolved: "github:Rynaro/ATLAS@<commit>"
    commit: "<commit>"
    tree: "<tree>"
    archive_sha256: "<sha256 or empty>"
    manifest_sha256: "<sha256 or empty>"
    verification: "verified"
```

Commit the lockfile. It gives teammates a stable, reviewable record of the
release content that was installed.

### Hash semantics

Each integrity field hashes a different surface; they are independent and
can be checked in any combination:

| Field | What it hashes | When it changes |
|-------|----------------|-----------------|
| `commit` | The Git commit SHA at the cloned tag's HEAD. | Whenever the upstream Eidolon retags or force-pushes its release. |
| `tree` | The Git tree SHA (`HEAD^{tree}`). Identical content → identical tree, regardless of commit history rewrites. | Whenever the *content* of the source repo at the tag changes. |
| `archive_sha256` | SHA-256 of `git archive --format=tar HEAD` produced by the upstream release workflow. | Whenever any tracked file changes. Cross-checked against the GitHub release asset by `roster-intake.yml`. |
| `manifest_sha256` | SHA-256 of the **single file** `./.eidolons/<name>/install.manifest.json` that the per-Eidolon `install.sh` writes after install. | Whenever the Eidolon's installer changes its declared `version`, `hosts_wired`, or `files`. |

`manifest_sha256` is a **file hash**, not a tree hash, by design:

- The installed `.eidolons/<name>/` directory contains files the Eidolon's
  `install.sh` shaped — possibly differently per host wiring or shared-dispatch
  preference — so a tree-wide hash there is not stable across legitimate
  re-installs.
- `install.manifest.json` is the EIIS-conformant declaration of what the
  installer claims it produced. Hashing it bit-for-bit gives a tamper-evident
  record of "what this install said it was" without coupling to host-wiring
  variability.
- Tree-wide content verification is handled by `archive_sha256` (a hash of the
  upstream source tarball, computed in CI by `eidolon-release-template.yml`),
  not by `manifest_sha256`.

## Cache Recovery

`fetch_eidolon` stores cloned Eidolon repos under `~/.eidolons/cache/<name>@<version>/`.
If the cache directory exists but is stale, corrupt, or represents a partial
(interrupted) clone, `fetch_eidolon` auto-recovers in one bounded retry:

1. **Detection.** Before using the cache, `fetch_eidolon` calls an internal
   integrity probe that returns one of:
   - `0` — cache is valid (HEAD resolvable and commit matches roster, or no
     roster metadata in compat mode and HEAD is resolvable).
   - `2` — cache-stale (HEAD resolves but commit/tree/archive hash mismatches
     the roster's expected values).
   - `3` — cache-corrupt (HEAD is unresolvable; `.git` is absent, partial, or
     damaged).

2. **Recovery.** On `rc ∈ {2, 3}`: the cache directory is removed and the
   Eidolon is re-cloned from the upstream tag. A `warn` log line reports the
   cache status and the re-clone URL.

3. **Strict re-verify.** After the fresh clone, the full integrity check runs
   again (die-on-failure). If the re-clone also mismatches the roster's commit,
   the install aborts with an explicit **upstream-truth mismatch** message:
   > `<name>@<version> commit mismatch persists after cache re-clone —
   > upstream tag at github.com/<repo> may have been force-moved.
   > Investigate roster vs. upstream attestation.`
   No third retry is attempted. A two-consecutive-failure outcome means the
   upstream tag itself disagrees with the roster and requires human review.

4. **Compat mode.** When a roster entry has no release metadata, HEAD
   resolvability is still checked (a corrupt git dir triggers rc=3 and re-clone
   even in compat mode). Commit/tree/archive comparisons are skipped.

5. **Idempotency.** A valid cache is reused on repeat runs without network
   access. Auto-recovery does not change the semantics of a subsequent
   `eidolons sync` run; the second run sees a fresh, valid cache and skips
   the re-clone.

### Doctor cache hygiene check

`eidolons doctor` includes a read-only `Cache hygiene` section that walks
`eidolons.lock` members and compares each `~/.eidolons/cache/<name>@<version>/`
entry against the roster's recorded commit. Stale or corrupt entries are
reported with an actionable next-step:

```
· atlas@1.3.0 cache stale (got abc1234def56, roster expects 7d9f3acf1f5f)
  — run 'eidolons sync' to auto-recover, or rm -rf ~/.eidolons/cache/atlas@1.3.0 to force
```

The doctor check is read-only; `--fix` delegates to `eidolons sync` which
exercises the auto-recovery path.

## Verification

Run:

```bash
eidolons verify
eidolons verify atlas spectra
```

The command is read-only. It compares lockfile entries with current roster
metadata and recomputes `install.manifest.json` checksums when installed
manifests exist.

GitHub artifact attestations are mandatory in CI intake and roster health when
release metadata declares `provenance.github_attestation: true`. Local runtime
installs do not require the GitHub CLI; checksum and Git object verification
remain the portable baseline.

## Release Automation

- Upstream Eidolon repos should use the reusable release workflow template in
  `.github/workflows/eidolon-release-template.yml` as the basis for their own
  release workflow.
- Nexus maintainers run `Roster Intake` with an Eidolon name and version. The
  workflow downloads the upstream release manifest, verifies checksums and the
  GitHub attestation, updates the roster, and opens a draft PR.
- Nexus releases are produced by `Release Nexus`, which validates the CLI,
  publishes checksummed artifacts, and generates GitHub/Sigstore attestations.

Enable GitHub immutable releases in the organization or repository settings
where available. Immutable releases prevent release assets and their Git tags
from being modified after publication.
