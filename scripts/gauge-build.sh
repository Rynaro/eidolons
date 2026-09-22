#!/usr/bin/env bash
# Explicit build-time Go dependency; never called by an ordinary CLI command.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-build}"
case "$mode" in build|package) ;; *) printf '%s\n' 'usage: gauge-build.sh build|package [output-directory]' >&2; exit 2 ;; esac
export GOTOOLCHAIN=local
command -v go >/dev/null 2>&1 || { printf '%s\n' 'Explicit Gauge builds require Go 1.27.1. Ordinary eidolons commands do not.' >&2; exit 1; }
[[ "$(go env GOVERSION)" == go1.27.1 ]] || { printf '%s\n' 'Gauge builds are pinned to Go 1.27.1; automatic toolchain downloads are disabled.' >&2; exit 1; }
cd "$root/gauge"
target_os="$(go env GOOS)"; target_arch="$(go env GOARCH)"
case "$target_os" in linux|darwin) ;; *) printf '%s\n' 'Gauge is qualified only for local Linux/macOS filesystems.' >&2; exit 1 ;; esac
if [[ "$mode" == package ]]; then
  output="${2:-$root/gauge/dist/$target_os-$target_arch}"
else
  output="${2:-$root/gauge/bin}"
fi
mkdir -p "$output"
output="$(cd "$output" && pwd)"
CGO_ENABLED=0 go build -mod=readonly -trimpath -buildvcs=false -ldflags=-buildid= -o "$output/eidolons-gauge" ./cmd/eidolons-gauge
if [[ "$mode" == package ]]; then
  mkdir -p "$output/licenses"
  cp "$root/LICENSE" "$output/LICENSE"
  cp "$(go env GOROOT)/LICENSE" "$output/licenses/Go-LICENSE"
  modules="$(CGO_ENABLED=0 go list -mod=readonly -deps -f '{{if .Module}}{{.Module.Path}}|{{.Module.Dir}}{{end}}' ./cmd/eidolons-gauge | sort -u)"
  while IFS='|' read -r module source; do
    [[ -n "$module" && "$module" != github.com/Rynaro/eidolons/gauge ]] || continue
    [[ -f "$source/LICENSE" ]] || { printf 'Missing required license for %s\n' "$module" >&2; exit 1; }
    label="${module//\//_}"
    cp "$source/LICENSE" "$output/licenses/$label-LICENSE"
  done <<< "$modules"
  printf 'Go: %s\nTarget: %s/%s\nBuild: CGO_ENABLED=0 -mod=readonly -trimpath -buildvcs=false -ldflags=-buildid=\nScope: one controller instance; local Linux/macOS only; no power-loss qualification\n' "$(go env GOVERSION)" "$target_os" "$target_arch" > "$output/BUILD.txt"
fi
printf '%s\n' "$output/eidolons-gauge"
