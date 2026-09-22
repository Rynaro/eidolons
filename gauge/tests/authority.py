"""Behavioral red: an existing valid writer must respect controller authority."""
import json
import os
import pathlib
import subprocess
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]


def main():
    with tempfile.TemporaryDirectory() as scratch:
        root = pathlib.Path(scratch)
        env = dict(os.environ, EIDOLONS_HOME=str(root / 'home'),
                   EIDOLONS_NEXUS=str(REPO), EIDOLONS_LEDGER_LOCK_TIMEOUT='1')
        command = [os.environ.get('LEDGER_TEST_BASH', 'bash'), str(REPO / 'cli/eidolons'),
                   'ledger', 'record', '--run-id', 'authority', '--type', 'probe']
        control = subprocess.run(command + ['--event-id', 'control'], cwd=root, env=env, capture_output=True)
        assert control.returncode == 0, control.stderr.decode()
        run = root / '.eidolons/.ledger/authority'
        original = (run / 'events/1.json').read_bytes()
        for version, phase in [(1, 'pending'), (1, 'active'), (999, 'active')]:
            (run / '.writer-authority.json').write_text(json.dumps({
                'schema_version': version, 'backend': 'gauge', 'phase': phase,
                'store_id': 'store-fixture', 'store_path': '/fixture/state.db',
                'root_id': 'authority', 'generation': 'generation-fixture', 'inventory': 'inventory-fixture'}))
            result = subprocess.run(command + ['--event-id', f'forbidden-{version}-{phase}'],
                                    cwd=root, env=env, capture_output=True)
            assert result.returncode != 0, f'Bash append accepted {version}/{phase} controller authority'
            assert len(list((run / 'events').iterdir())) == 1, 'refused append published an event'
            assert (run / 'events/1.json').read_bytes() == original
        print('existing writer control passed; staged, promoted and future authority append refusals passed')


if __name__ == '__main__':
    main()
