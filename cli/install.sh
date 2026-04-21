#!/usr/bin/env bash
#
# eidolons — bootstrap installer
# ═══════════════════════════════════════════════════════════════════════════
#
# Installs the `eidolons` CLI globally and caches the nexus.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
#
# Or, with overrides:
#   curl -sSL .../install.sh | EIDOLONS_REF=v1.0.0 bash
#   curl -sSL .../install.sh | EIDOLONS_BIN_DIR=/usr/local/bin bash
#
# Environment:
#   EIDOLONS_REPO     Nexus repo URL (default: https://github.com/Rynaro/eidolons)
#   EIDOLONS_REF      Branch/tag to install (default: main)
#   EIDOLONS_HOME     Nexus cache (default: $HOME/.eidolons)
#   EIDOLONS_BIN_DIR  Where to symlink the CLI (default: $HOME/.local/bin)
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

EIDOLONS_REPO="${EIDOLONS_REPO:-https://github.com/Rynaro/eidolons}"
EIDOLONS_REF="${EIDOLONS_REF:-main}"
EIDOLONS_HOME="${EIDOLONS_HOME:-$HOME/.eidolons}"
EIDOLONS_BIN_DIR="${EIDOLONS_BIN_DIR:-$HOME/.local/bin}"

# ─── Pretty output ─────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi

say()  { printf "%s▸%s %s\n"  "$BOLD"  "$RESET" "$*"; }
ok()   { printf "%s✓%s %s\n"  "$GREEN" "$RESET" "$*"; }
warn() { printf "%s⚠%s %s\n"  "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf "%s✗%s %s\n"  "$RED"   "$RESET" "$*" >&2; exit 1; }

# ─── Banner ────────────────────────────────────────────────────────────────
cat <<EOF
${BOLD}╔═══════════════════════════════════════════╗
║   Eidolons — Bootstrap Installer          ║
╚═══════════════════════════════════════════╝${RESET}
EOF

# ─── Prerequisites ─────────────────────────────────────────────────────────
say "Checking prerequisites"

need() { command -v "$1" >/dev/null 2>&1 || die "Missing: $1 ($2)"; }
need git  "required to clone the nexus and fetch Eidolon repos"
need bash "required — the CLI is bash"
need jq   "required for JSON parsing in CLI commands"

if ! command -v yq >/dev/null 2>&1; then
  warn "yq not found — falling back to internal YAML parser (slower, less strict)"
fi

ok "Prerequisites OK"

# ─── Install the nexus ─────────────────────────────────────────────────────
mkdir -p "$EIDOLONS_HOME" "$EIDOLONS_BIN_DIR"

if [[ -d "$EIDOLONS_HOME/nexus/.git" ]]; then
  say "Updating existing nexus at $EIDOLONS_HOME/nexus"
  git -C "$EIDOLONS_HOME/nexus" fetch --depth 1 origin "$EIDOLONS_REF" >/dev/null
  git -C "$EIDOLONS_HOME/nexus" checkout -q "$EIDOLONS_REF"
  git -C "$EIDOLONS_HOME/nexus" reset --hard "origin/$EIDOLONS_REF" >/dev/null
  ok "Nexus updated to $EIDOLONS_REF"
else
  say "Cloning nexus from $EIDOLONS_REPO ($EIDOLONS_REF)"
  git clone --depth 1 --branch "$EIDOLONS_REF" "$EIDOLONS_REPO" "$EIDOLONS_HOME/nexus" >/dev/null 2>&1 \
    || die "Failed to clone $EIDOLONS_REPO"
  ok "Nexus cloned to $EIDOLONS_HOME/nexus"
fi

# ─── Install the CLI ──────────────────────────────────────────────────────
say "Installing CLI"

CLI_SRC="$EIDOLONS_HOME/nexus/cli/eidolons"
CLI_DST="$EIDOLONS_BIN_DIR/eidolons"

[[ -f "$CLI_SRC" ]] || die "CLI entrypoint missing at $CLI_SRC (nexus clone may be corrupt)"

chmod +x "$CLI_SRC"
ln -sf "$CLI_SRC" "$CLI_DST"

ok "CLI symlinked to $CLI_DST"

# ─── Post-install guidance ────────────────────────────────────────────────
echo ""
printf "%sDone.%s\n" "$GREEN" "$RESET"
echo ""

# Check PATH
if ! echo "$PATH" | tr ':' '\n' | grep -Fxq "$EIDOLONS_BIN_DIR"; then
  warn "$EIDOLONS_BIN_DIR is not on your PATH."
  echo ""
  echo "  Add to your shell rc (e.g. ~/.bashrc, ~/.zshrc):"
  echo "    ${BOLD}export PATH=\"$EIDOLONS_BIN_DIR:\$PATH\"${RESET}"
  echo ""
fi

cat <<EOF
Next steps:
  ${BOLD}eidolons --help${RESET}                          show all commands
  ${BOLD}eidolons list${RESET}                            browse the roster
  ${BOLD}cd <your-project> && eidolons init${RESET}       set up a project

Docs:       $EIDOLONS_HOME/nexus/docs/
Nexus repo: $EIDOLONS_REPO
EOF
