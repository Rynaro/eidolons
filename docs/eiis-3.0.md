# EIIS 3.0 integration

The normative EIIS 3.0 contract lives in
[`Rynaro/eidolons-eiis/spec/eiis-3.0.md`](https://github.com/Rynaro/eidolons-eiis/blob/main/spec/eiis-3.0.md).
The nexus does not redefine that contract.

The v3 rollout is ordered:

1. Merge and release [`Rynaro/eidolons-eiis#5`](https://github.com/Rynaro/eidolons-eiis/pull/5) as `v3.0.0`.
2. Merge the nexus v3 change, which sets `eiis_required: "3.0.0"`.
3. Publish v3-conformant releases of each roster member.
4. Update roster pins only after each member passes the released EIIS checker.

The nexus provides orchestration-level checks in `doctor --deep` and host-hook
registration checks in `eidolons harness check`. The upstream EIIS checker is
the authority for repository, installer, manifest, canonical-tree, adapter,
inventory, and hook conformance.
