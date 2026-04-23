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
EIDOLONS_YQ_VERSION="${EIDOLONS_YQ_VERSION:-v4.44.3}"

# ─── Pretty output ─────────────────────────────────────────────────────────
# install.sh runs *before* the nexus exists on disk, so it can't source the
# UI layer at cli/src/ui/. The palette + ui_banner are inlined here and
# kept in sync with cli/src/ui/themes/default.sh by hand.
_install_fancy() {
  [[ -n "${NO_COLOR:-}" ]] && return 1
  [[ "${FORCE_COLOR:-0}" == "1" ]] && return 0
  [[ -n "${CI:-}" ]] && return 1
  [[ -t 1 ]]
}

if _install_fancy; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
  AMBER=$'\033[38;5;214m'; MUTED=$'\033[38;5;243m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; RESET=""
  AMBER=""; MUTED=""
fi

say()  { printf "%s▸%s %s\n"  "$BOLD"  "$RESET" "$*"; }
ok()   { printf "%s✓%s %s\n"  "$GREEN" "$RESET" "$*"; }
warn() { printf "%s⚠%s %s\n"  "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf "%s✗%s %s\n"  "$RED"   "$RESET" "$*" >&2; exit 1; }

# ─── Banner ────────────────────────────────────────────────────────────────
# Cozy CRT wordmark. In plain mode (CI / non-TTY / NO_COLOR) we drop the
# block art and print a single-line marker so install logs stay grep-able.
if _install_fancy; then
  printf '\n'
  printf '%s███████╗██╗██████╗  ██████╗ ██╗      ██████╗ ███╗   ██╗███████╗%s\n' "$AMBER" "$RESET"
  printf '%s██╔════╝██║██╔══██╗██╔═══██╗██║     ██╔═══██╗████╗  ██║██╔════╝%s\n' "$AMBER" "$RESET"
  printf '%s█████╗  ██║██║  ██║██║   ██║██║     ██║   ██║██╔██╗ ██║███████╗%s\n' "$AMBER" "$RESET"
  printf '%s██╔══╝  ██║██║  ██║██║   ██║██║     ██║   ██║██║╚██╗██║╚════██║%s\n' "$AMBER" "$RESET"
  printf '%s███████╗██║██████╔╝╚██████╔╝███████╗╚██████╔╝██║ ╚██╗██║███████║%s\n' "$AMBER" "$RESET"
  printf '%s╚══════╝╚═╝╚═════╝  ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝%s\n'   "$AMBER" "$RESET"
  printf '  %s· bootstrap installer ·%s\n\n' "$MUTED" "$RESET"
else
  printf 'Eidolons — Bootstrap Installer\n\n'
fi

# ─── Prerequisites ─────────────────────────────────────────────────────────
say "Checking prerequisites"

need() { command -v "$1" >/dev/null 2>&1 || die "Missing: $1 ($2)"; }
need git  "required to clone the nexus and fetch Eidolon repos"
need bash "required — the CLI is bash"
need jq   "required for JSON parsing in CLI commands"

ok "Prerequisites OK"

# ─── yq (YAML parser) ──────────────────────────────────────────────────────
# yq is a hard dependency — every CLI command reads YAML. Auto-install the
# mikefarah/yq static binary when missing so users never hit
# "ModuleNotFoundError: No module named 'yaml'" from a Python fallback.
install_yq() {
  local os arch asset url dest
  case "$(uname -s)" in
    Linux)  os="linux" ;;
    Darwin) os="darwin" ;;
    *)      die "Unsupported OS for automatic yq install: $(uname -s). Install yq manually: https://github.com/mikefarah/yq/releases" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)             die "Unsupported arch for automatic yq install: $(uname -m). Install yq manually: https://github.com/mikefarah/yq/releases" ;;
  esac
  asset="yq_${os}_${arch}"
  url="https://github.com/mikefarah/yq/releases/download/${EIDOLONS_YQ_VERSION}/${asset}"
  dest="$EIDOLONS_BIN_DIR/yq"

  mkdir -p "$EIDOLONS_BIN_DIR"
  say "Downloading yq ${EIDOLONS_YQ_VERSION} (${os}/${arch}) → $dest"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest" || die "Failed to download yq from $url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url" || die "Failed to download yq from $url"
  else
    die "Need curl or wget to auto-install yq. Install yq manually: https://github.com/mikefarah/yq/releases"
  fi

  chmod +x "$dest"
  "$dest" --version >/dev/null 2>&1 || die "yq binary at $dest failed to execute. Remove it and install yq manually."
  ok "yq installed to $dest"
}

if command -v yq >/dev/null 2>&1; then
  ok "yq already present ($(command -v yq))"
else
  install_yq
fi

# ─── Install the nexus ─────────────────────────────────────────────────────
mkdir -p "$EIDOLONS_HOME" "$EIDOLONS_BIN_DIR"

# Fetch-based flow (init + fetch + checkout FETCH_HEAD) so EIDOLONS_REF
# accepts branch names, tags, AND commit SHAs uniformly. `git clone
# --branch` rejects SHAs — users pinning to a specific commit (or CI
# passing ${{ github.sha }}) would fail otherwise.
NEXUS_DIR="$EIDOLONS_HOME/nexus"
if [[ -d "$NEXUS_DIR/.git" ]]; then
  say "Updating existing nexus at $NEXUS_DIR ($EIDOLONS_REF)"
  git -C "$NEXUS_DIR" fetch --depth 1 origin "$EIDOLONS_REF" >/dev/null 2>&1 \
    || die "Failed to fetch $EIDOLONS_REF from $EIDOLONS_REPO"
  git -C "$NEXUS_DIR" reset --hard FETCH_HEAD >/dev/null
  ok "Nexus updated to $EIDOLONS_REF"
else
  say "Cloning nexus from $EIDOLONS_REPO ($EIDOLONS_REF)"
  mkdir -p "$NEXUS_DIR"
  git -C "$NEXUS_DIR" init -q >/dev/null 2>&1 \
    || die "Failed to init git repo at $NEXUS_DIR"
  git -C "$NEXUS_DIR" remote add origin "$EIDOLONS_REPO" 2>/dev/null \
    || git -C "$NEXUS_DIR" remote set-url origin "$EIDOLONS_REPO"
  git -C "$NEXUS_DIR" fetch --depth 1 origin "$EIDOLONS_REF" >/dev/null 2>&1 \
    || die "Failed to fetch $EIDOLONS_REF from $EIDOLONS_REPO"
  git -C "$NEXUS_DIR" checkout -q FETCH_HEAD \
    || die "Failed to checkout FETCH_HEAD in $NEXUS_DIR"
  ok "Nexus cloned to $NEXUS_DIR"
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
