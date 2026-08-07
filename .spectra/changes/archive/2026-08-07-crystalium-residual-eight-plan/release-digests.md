# Published image digests (resolved from the ghcr REGISTRY, never from release notes)

Image tags are un-prefixed: `2.0.2`, not `v2.0.2`.

| version | index digest | media type | arches | resolved |
|---|---|---|---|---|
| 2.0.2 | `sha256:ce21b9b58f05ce5715537ac7aa0ee4acef36f55e9a423a7473c0fbe0eb5d95d7` | `application/vnd.oci.image.index.v1+json` | amd64, arm64 | 2026-08-06 |

Method: `curl` against `https://ghcr.io/v2/rynaro/crystalium/manifests/<tag>` with an
`Accept:` header for the OCI index type, reading `docker-content-digest` from the RESPONSE
HEADERS. This is the index (multi-arch) digest, which is what the roster must pin — a
per-arch manifest digest would pin one platform and silently break the other.

## Roster-bump sequencing — a deliberate, stated deviation

The plan runs the full chain per batch: tag -> image -> digest -> roster PR (BOTH
`roster/mcps.yaml` and `roster/index.yaml` in ONE commit, since crystalium is dual-rostered
and skew-guarded) -> nexus release -> integrity PR.

v2.0.2 and v2.1.0 land within the same campaign session, minutes apart. Running two full
nexus release chains — each with a hand-verified integrity PR that gets NO CI — would be
churn without a consumer: no external consumer can pin 2.0.2 in the interval.

**Decision:** capture the 2.0.2 digest HERE, at the moment it is authoritative and from the
registry (so it is never reconstructed from memory later), and run ONE roster bump to the
final campaign version. The 2.0.2 digest above remains the record that the image was built,
published multi-arch, and verified.

This is a deviation from the plan's letter and is recorded as such rather than absorbed
silently. It does NOT skip any verification: the digest is registry-resolved either way, and
`eidolons mcp verify` still runs against whatever the roster finally pins (exit 3 =
INDETERMINATE, not a pass).
