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
