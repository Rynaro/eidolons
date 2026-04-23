#!/usr/bin/env bash
# cli/tests/ui-preview.sh — visual smoke test for the cozy TUI layer.
#
# Not run by CI. Pipe to `less -R` to read the colored output, or just
# scroll your terminal. Forces FORCE_COLOR=1 so you see the fancy path
# even when stderr isn't a TTY.
#
# Usage:
#   bash cli/tests/ui-preview.sh           # everything
#   bash cli/tests/ui-preview.sh roster    # one section
#
# Sections: banner, roster, list, doctor, dispatch, prompts
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

EIDOLONS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
export EIDOLONS_HOME="${EIDOLONS_HOME:-$HOME/.eidolons}"
export FORCE_COLOR=1

CLI="$EIDOLONS_ROOT/cli/eidolons"

want="${1:-all}"
match() { [[ "$want" == "all" || "$want" == "$1" ]]; }

if match banner; then
  printf '\n\033[1;33m== banner / help ==\033[0m\n'
  bash "$CLI" --help || true
fi

if match roster; then
  printf '\n\033[1;33m== eidolons roster (team view, cards) ==\033[0m\n'
  bash "$EIDOLONS_ROOT/cli/src/roster.sh" || true

  printf '\n\033[1;33m== eidolons roster atlas (single card) ==\033[0m\n'
  bash "$EIDOLONS_ROOT/cli/src/roster.sh" atlas || true
fi

if match list; then
  printf '\n\033[1;33m== eidolons list --available (card stack) ==\033[0m\n'
  bash "$EIDOLONS_ROOT/cli/src/list.sh" --available || true
fi

if match doctor; then
  printf '\n\033[1;33m== eidolons doctor (section panels) ==\033[0m\n'
  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    cat > eidolons.yaml <<'YAML'
version: 1
hosts:
  wire: [claude-code]
  shared_dispatch: false
members:
  - name: atlas
    version: "^1.0.3"
    source: github:Rynaro/ATLAS
YAML
    bash "$EIDOLONS_ROOT/cli/src/doctor.sh" || true
  )
  rm -rf "$tmp"
fi

if match dispatch; then
  printf '\n\033[1;33m== eidolons spectra --help (subcommand list) ==\033[0m\n'
  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    mkdir -p .eidolons/spectra/commands
    printf '#!/usr/bin/env bash\necho fit\n' > .eidolons/spectra/commands/fit.sh
    printf '#!/usr/bin/env bash\necho score\n' > .eidolons/spectra/commands/score.sh
    chmod +x .eidolons/spectra/commands/*.sh
    bash "$EIDOLONS_ROOT/cli/src/dispatch_eidolon.sh" spectra --help || true
  )
  rm -rf "$tmp"
fi

if match prompts; then
  printf '\n\033[1;33m== ui_confirm / ui_input demo (interactive — answer the prompts) ==\033[0m\n'
  bash -c "
    . '$EIDOLONS_ROOT/cli/src/ui/theme.sh'
    . '$EIDOLONS_ROOT/cli/src/ui/prompt.sh'
    if ui_confirm 'Try a default-yes confirm?' default-y; then
      echo 'you said yes'
    else
      echo 'you said no'
    fi
    name=\"\$(ui_input 'What is your name' 'henrique')\"
    echo \"got: \$name\"
  "
fi

printf '\n\033[2m(end of preview)\033[0m\n'
