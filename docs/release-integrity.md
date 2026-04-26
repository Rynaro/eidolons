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
