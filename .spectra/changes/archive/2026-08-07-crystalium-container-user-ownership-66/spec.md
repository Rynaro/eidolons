# crystalium#66 — containers write into the bind-mounted source tree as root

**maker:** claude-opus-5 · **checker:** kupo · **tier:** full · **repo:** Rynaro/crystalium

## Problem

`docker-compose.yml` bind-mounts the source tree read-write (`.:/app`) and carries no `user:`
key; the Dockerfile adds no `USER`, so `python:3.12-slim` runs as root. Every
`docker compose run` therefore leaves `__pycache__/`, `.pytest_cache/`, `.ruff_cache/` and the
`.venv` mountpoint on the host owned by uid 0.

Measured, not inferred:

| where | root-owned paths |
|---|---|
| a normal checkout at `d1691db` | **297** |
| 17 residual-eight campaign worktrees | **2353** across **96M** |
| a pristine clone after ONE pre-fix `docker compose run` | **24**, from zero |

The consequence is not cosmetic. `git worktree remove` deregisters a worktree from
`.git/worktrees/` *before* it fails to delete the directory, so a failed cleanup leaves a
partially-deleted orphan git no longer tracks — five worktrees ended up in that state during
the residual-eight cleanup, and 96M could not be reclaimed without `sudo`.

## Decision

Pin the compose service to the invoking user. Scope the change to the **dev/compose path only**;
the published image is left untouched.

That last point is the load-bearing one. The published image is built from `target: base`
(`release.yml:86`) and is launched by the eidolons MCP wiring as:

```
docker run --rm -i -v <host>/.crystalium/eidolons:/root/.crystalium/eidolons \
  -e CRYSTALIUM_DATA_DIR=/root/.crystalium/eidolons ghcr.io/rynaro/crystalium@sha256:...
```

Adding a non-root `USER` to `base` — which issue #66's own sketch proposed — would make that
path unwritable and break **every existing consumer wiring**. A `--user` pin belongs on that
`docker run` invocation, where the bind mount already carries host ownership, not baked into
the image. So `base` keeps running as root and keeps resolving its data dir under `$HOME`.

Two consequences of running non-root under compose, both discovered by execution:

1. **`/root` is mode 0700.** The dev data volume mounted at `/root/.crystalium` becomes
   unopenable — SQLite/LanceDB/Kuzu all fail. Moved to `/data`, pre-created 1777 in the dev
   stage so a *fresh named volume inherits that mode* and is writable by any host uid.
   Hardcoding uid 1000 would break every developer whose `id -u` differs.
2. **`uv` initialises a cache under `$HOME` before the entrypoint reaches Python.** As a
   non-root uid `HOME` defaults to `/`, and uv dies with
   `Failed to initialize cache at /.cache/uv: Permission denied`. `HOME=/tmp` fixes it;
   measured that `HOME` alone suffices, no separate `UV_CACHE_DIR`.

## Safety invariant

The published image's default user, entrypoint and data-dir resolution are unchanged. Any
consumer wiring that works against `2.1.0` works unchanged after this. The only user-visible
change is to the *dev* container and the *dev* scratch volume.

## Known gaps

- The `- /app/.venv` anonymous-volume mountpoint is still created root-owned, and `user:`
  cannot change that: the Docker **daemon** creates it, not the container process. It is an
  empty directory in a developer-owned parent, so `rmdir` clears it without sudo. The gate
  measures removability rather than ownership specifically so this does not require an
  exception entry.
- Existing checkouts still carry pre-change root-owned caches. `make fix-ownership` migrates
  them; there is no way to make an existing tree self-heal without a root-capable step.
- CI cannot regression-test the published image's `--user` story, because that pin lives in
  the nexus templates, not in this repo.

## Outcome

Suite: **1097 passed, 4 skipped, 1 xfailed, exit 0**. Running non-root revives two tests that
were structurally unable to fail as root — `test_doctor_readonly_data_dir_nonzero` and
`test_doctor_fail_shows_fail_marker`, which self-skip with *"Running as root; chmod 0o444 does
not prevent writes for root"*. Both exist to verify `doctor` reports failure on an unwritable
data dir, which is exactly the property root cannot exercise.
