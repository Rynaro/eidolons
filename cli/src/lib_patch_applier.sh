#!/usr/bin/env bash
# lib_patch_applier — deterministic, fuzzy edit applier (roadmap: Kupo executor)
# ═══════════════════════════════════════════════════════════════════════════
# The mechanical bridge between an Eidolon's EMITTED edit-text (search/replace
# blocks or whole-file content) and actual file changes. It is the harness-owned
# applier the frontier research mandates: small models cannot reliably HAND-APPLY
# diffs (disabling a fuzzy applier ~9x's edit errors), so the model emits intent
# and this deterministic, non-LLM library reconciles it.
#
# Discipline (mirrors `eidolons sandbox`'s diff-not-apply philosophy):
#   - Applies ONLY under an explicit --root (a SCRATCH sandbox copy). There is no
#     default-to-cwd: nothing writes the real tree by accident.
#   - Refuses paths containing '..' (no escaping the root; matches ECL's path rule).
#   - Deterministic + idempotent: same proposal + same tree -> same result.
#   - bash 3.2 compatible (no associative arrays / mapfile / ${var,,}). Core match
#     is pure awk so it is portable wherever the rest of the CLI runs.
#
# Fuzzy ladder (first match wins, least-fuzzy first):
#   level 1  exact match (trailing whitespace normalized)
#   level 2  relative-indent match (leading+trailing whitespace normalized)
#
# Proposal schema (see schemas note in the Kupo repo, kupo-edit-proposal.v1.json):
#   { "edits": [
#       {"op":"search_replace","path":"a/b.py","search":"<block>","replace":"<block>"},
#       {"op":"write_file","path":"a/c.py","content":"<whole file>"}
#   ] }

# ── pa_sha256 <file> : portable sha256 (shasum or sha256sum), 64-hex only ─────
pa_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else echo ""; fi
}

# ── pa_search_replace_file <file> <searchfile> <replacefile> ──────────────────
# Applies the first matching search-block -> replace-block in <file>, in place.
# Echoes "<level>:<start_line>" on success; returns 3 (not found) / 2 (bad args).
pa_search_replace_file() {
  local file="$1" sf="$2" rf="$3"
  [ -f "$file" ] || return 2
  local out level start
  for level in 1 2; do
    out="$(awk -v sf="$sf" -v rf="$rf" -v fuzzy="$level" '
      function norm(s){ sub(/[ \t]+$/,"",s); if(fuzzy==2){ sub(/^[ \t]+/,"",s) } return s }
      BEGIN{
        ns=0; while((getline l < sf)>0){ s[++ns]=l; sn[ns]=norm(l) }
        nr=0; while((getline l < rf)>0){ r[++nr]=l }
        close(sf); close(rf)
        if(ns==0){ print "__EMPTY_SEARCH__" > "/dev/stderr"; exit 2 }
      }
      { src[NR]=$0; srcn[NR]=norm($0) }
      END{
        total=NR; start=0
        for(i=1;i+ns-1<=total;i++){
          ok=1
          for(j=1;j<=ns;j++){ if(srcn[i+j-1]!=sn[j]){ ok=0; break } }
          if(ok){ start=i; break }
        }
        if(start==0){ exit 3 }
        for(i=1;i<start;i++)      print src[i]
        for(j=1;j<=nr;j++)        print r[j]
        for(i=start+ns;i<=total;i++) print src[i]
        print start > "/dev/stderr"   # report the matched start line on stderr
      }
    ' "$file" 2>"$file.pa_ln")"
    local rc=$?
    if [ "$rc" -eq 0 ]; then
      start="$(cat "$file.pa_ln" 2>/dev/null | tail -n1)"
      rm -f "$file.pa_ln"
      printf '%s\n' "$out" > "$file.pa_tmp" && mv "$file.pa_tmp" "$file"
      echo "${level}:${start}"
      return 0
    fi
    rm -f "$file.pa_ln"
    [ "$rc" -eq 2 ] && return 2   # empty search block — don't try fuzzier
  done
  return 3
}

# ── pa_apply_proposal <proposal.json> <root> : echoes result JSON, exit 0 if all OK
pa_apply_proposal() {
  local proposal="$1" root="$2"
  [ -f "$proposal" ] || { echo '{"error":"proposal not found"}'; return 2; }
  [ -d "$root" ]     || { echo '{"error":"root not a directory (need an explicit scratch --root)"}'; return 2; }
  command -v jq >/dev/null 2>&1 || { echo '{"error":"jq required"}'; return 2; }

  local n; n="$(jq '.edits | length' "$proposal" 2>/dev/null || echo 0)"
  local i applied=0 failed=0 results="[]"
  for ((i=0; i<n; i++)); do
    local op path target status detail sha
    op="$(jq -r ".edits[$i].op // \"\"" "$proposal")"
    path="$(jq -r ".edits[$i].path // \"\"" "$proposal")"
    status="error"; detail=""; sha=""
    target="$root/$path"

    case "$path" in
      ""|*..*) status="error"; detail="unsafe or empty path" ;;
      *)
        case "$op" in
          write_file)
            mkdir -p "$(dirname "$target")" 2>/dev/null || true
            if jq -r ".edits[$i].content // \"\"" "$proposal" > "$target"; then
              status="applied"; detail="write_file"; sha="$(pa_sha256 "$target")"
            else status="error"; detail="write failed"; fi
            ;;
          search_replace)
            if [ ! -f "$target" ]; then status="not_found"; detail="target file missing"
            else
              local sf rf res sblock rblock rc
              sblock="$(jq -r ".edits[$i].search  // \"\"" "$proposal")"
              rblock="$(jq -r ".edits[$i].replace // \"\"" "$proposal")"
              # Command substitution strips jq -r's trailing newline; re-add exactly
              # one so awk reads the intended line count (empty replace = deletion).
              if [ -z "$sblock" ]; then
                status="error"; detail="empty search block"
              else
                sf="$(mktemp)"; rf="$(mktemp)"
                printf '%s\n' "$sblock" > "$sf"
                if [ -n "$rblock" ]; then printf '%s\n' "$rblock" > "$rf"; else : > "$rf"; fi
                if res="$(pa_search_replace_file "$target" "$sf" "$rf")"; then
                  status="applied"; detail="search_replace level=${res%%:*} line=${res##*:}"
                  sha="$(pa_sha256 "$target")"
                else
                  rc=$?
                  if [ "$rc" -eq 3 ]; then status="not_found"; detail="search block not found"
                  else status="error"; detail="bad search block"; fi
                fi
                rm -f "$sf" "$rf"
              fi
            fi
            ;;
          *) status="error"; detail="unknown op: $op" ;;
        esac
        ;;
    esac

    if [ "$status" = "applied" ]; then applied=$((applied+1)); else failed=$((failed+1)); fi
    results="$(printf '%s' "$results" | jq \
      --arg path "$path" --arg op "$op" --arg status "$status" --arg detail "$detail" --arg sha "$sha" \
      '. + [{path:$path, op:$op, status:$status, detail:$detail, sha256:$sha}]')"
  done

  jq -nc --argjson applied "$applied" --argjson failed "$failed" --argjson results "$results" \
    '{applied:$applied, failed:$failed, ok:($failed==0), results:$results}'
  [ "$failed" -eq 0 ]
}
