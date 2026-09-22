# Historical install-state snapshots

`sources.tsv` pins each original release commit and compressed archive SHA-256.
Every archive contains exactly these unmodified paths from that commit:

- `.gitignore`
- `VERSION`
- `cli/eidolons`
- `cli/src/upgrade.sh`
- `roster/index.yaml`

These are reduced snapshots, not complete historical installations. The actual
old dispatcher can report its version; other CLI resources and operations are
omitted. Tests initialize an isolated Git repository and model installation
sidecars separately. They invoke the current `cli/src/upgrade_self.sh` directly
against that old tree. Invoking the current dispatcher with a complete old nexus
would select the old updater, so this is not a claim of retroactive repair.

The old installer could already have modified tracked `.gitignore`. Such
pre-existing changes remain protected and rejected, even when they contain only
`.roster_ref`: their bytes cannot prove who authored them. The passing migration
matrix starts from clean historical tracked files.

To regenerate with the original commits available locally, run from the
repository root (Python and Git):

```python
import gzip
import hashlib
from pathlib import Path
import subprocess

fixtures = Path("cli/tests/fixtures/legacy-upgrade")
paths = [".gitignore", "VERSION", "cli/eidolons", "cli/src/upgrade.sh", "roster/index.yaml"]
for row in (fixtures / "sources.tsv").read_text().splitlines():
    if row.startswith("#"):
        continue
    version, commit, expected = row.split("\t")
    archive = subprocess.check_output(["git", "archive", "--format=tar", commit, "--", *paths])
    compressed = gzip.compress(archive, mtime=0)
    # Compression library versions can change compressed bytes; extracted
    # file bytes must always match `git show COMMIT:PATH` for all five paths.
    assert hashlib.sha256(compressed).hexdigest() == expected
    (fixtures / f"{version}.tar.gz").write_bytes(compressed)
```

Extract a fixture with `tar -xzf <version>.tar.gz -C <empty-directory>`.
The target fixture is independently built from current CLI source and receives
real commit, tree, and archive hashes in a post-tag metadata commit. Tests never
use force, advisory integrity policy, or an unverified escape hatch.
