#!/usr/bin/env bash
# Nexus-owned EIIS v3 host adapter rendering.

EIIS_V3_POINTER_MAX_BYTES=2048

_eiis_v3_pointer_write() {
  local path="$1" name="$2" description="$3" persona="$4" spec="$5" tools_csv="${6:-}"
  mkdir -p "$(dirname "$path")"
  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    [[ -z "$tools_csv" ]] || printf 'tools: [%s]\n' "$tools_csv"
    printf '%s\n' 'generated_by: eidolons' '---' ''
    printf 'Load `%s` and `%s`. This file is a disposable discovery adapter.\n' "$persona" "$spec"
  } > "$path"
}

# _eiis_v3_capability_class NAME
# Resolve the roster-owned capability class without importing package prose.
_eiis_v3_capability_class() {
  local name="$1" roster="${EIDOLONS_NEXUS:-${NEXUS:-}}/roster/index.yaml"
  [[ -f "$roster" ]] || return 1
  awk -v wanted="$name" '
    $0 ~ "^  - name: " wanted "$" { found=1; next }
    found && /^  - name:/ { exit }
    found && /^    capability_class:/ { sub(/^    capability_class:[[:space:]]*/, ""); print; exit }
  ' "$roster"
}

# _eiis_v3_claude_tools NAME
# The policy is versioned separately from package manifests. Unknown classes
# fail closed to an explicit empty allowance rather than inheriting every tool.
_eiis_v3_claude_tools() {
  local name="$1" klass map tools
  klass="$(_eiis_v3_capability_class "$name" 2>/dev/null || true)"
  map="${EIDOLONS_NEXUS:-${NEXUS:-}}/roster/host-capabilities.json"
  [[ -n "$klass" && -f "$map" ]] || { printf '%s' ''; return 0; }
  tools="$(jq -r --arg c "$klass" '.hosts["claude-code"].classes[$c] // [] | join(", ")' "$map" 2>/dev/null || true)"
  printf '%s' "$tools"
}

_eiis_v3_skill_adapter() {
  local name="$1" skill="$2" entry="$3"
  local dir=".claude/skills/${name}-${skill}" path link_target
  path="$dir/SKILL.md"
  mkdir -p "$dir"
  link_target="../../../.eidolons/${name}/${entry}"
  if [[ "${EIDOLONS_NO_SYMLINKS:-0}" != "1" ]]; then
    rm -f "$path"
    if ln -s "$link_target" "$path" 2>/dev/null && [[ -e "$path" ]]; then
      printf 'symlink\t%s\t.eidolons/%s/%s\n' "$path" "$name" "$entry"
      return 0
    fi
    rm -f "$path"
  fi
  _eiis_v3_pointer_write "$path" "${name}-${skill}" \
    "Load the canonical ${name}/${skill} skill." \
    ".eidolons/${name}/${entry}" ".eidolons/${name}/SPEC.md"
  printf 'pointer\t%s\t.eidolons/%s/%s\n' "$path" "$name" "$entry"
}

eiis_v3_render_adapters() {
  local name="$1" hosts_csv="$2" root=".eidolons/$1"
  local manifest="$root/manifest.json" receipt="$root/install.receipt.json"
  [[ -f "$manifest" && -f "$root/PERSONA.md" && -f "$root/SPEC.md" ]] || return 1

  local display description host skill entry adapter_lines="" line type path canonical
  display="$(jq -r '.methodology // .name' "$manifest")"
  description="$display methodology agent; canonical content is installed under $root."

  # Migrate v1 installer-owned surfaces. These paths are scoped by the
  # member slug; canonical package content is never touched.
  rm -f ".codex/agents/$name.md" ".github/instructions/$name.instructions.md"
  if [[ -d .claude/skills ]]; then
    local old_adapter old_skill declared
    for old_adapter in .claude/skills/${name}-*/SKILL.md; do
      [[ -e "$old_adapter" || -L "$old_adapter" ]] || continue
      old_skill="$(basename "$(dirname "$old_adapter")")"
      old_skill="${old_skill#${name}-}"
      declared="$(jq -r --arg s "$old_skill" '.skills | has($s)' "$manifest")"
      if [[ "$declared" != "true" ]]; then
        rm -f "$old_adapter"
        rmdir "$(dirname "$old_adapter")" 2>/dev/null || true
      fi
    done
  fi

  for host in $(printf '%s' "$hosts_csv" | tr ',' ' '); do
    case "$host" in
      claude-code)
        local claude_tools
        claude_tools="$(_eiis_v3_claude_tools "$name")"
        _eiis_v3_pointer_write ".claude/agents/$name.md" "$name" "$description" \
          "$root/PERSONA.md" "$root/SPEC.md" "$claude_tools"
        adapter_lines="${adapter_lines}pointer\t.claude/agents/$name.md\t$root/PERSONA.md\n"
        while IFS=$'\t' read -r skill entry; do
          [[ -n "$skill" ]] || continue
          line="$(_eiis_v3_skill_adapter "$name" "$skill" "$entry")"
          adapter_lines="${adapter_lines}${line}\n"
        done < <(jq -r '.skills | to_entries[]? | [.key,.value.entrypoint] | @tsv' "$manifest")
        ;;
      codex)
        mkdir -p .codex/agents
        {
          printf 'name = "%s"\n' "$name"
          printf 'description = "%s"\n' "$description"
          printf 'developer_instructions = "Load %s/PERSONA.md and %s/SPEC.md."\n' "$root" "$root"
          printf '# generated_by: eidolons\n'
        } > ".codex/agents/$name.toml"
        adapter_lines="${adapter_lines}pointer\t.codex/agents/$name.toml\t$root/PERSONA.md\n"
        ;;
      copilot)
        _eiis_v3_pointer_write ".github/agents/$name.agent.md" "$name" "$description" \
          "$root/PERSONA.md" "$root/SPEC.md"
        adapter_lines="${adapter_lines}pointer\t.github/agents/$name.agent.md\t$root/PERSONA.md\n"
        ;;
      opencode)
        _eiis_v3_pointer_write ".opencode/agents/$name.md" "$name" "$description" \
          "$root/PERSONA.md" "$root/SPEC.md"
        adapter_lines="${adapter_lines}pointer\t.opencode/agents/$name.md\t$root/PERSONA.md\n"
        ;;
      cursor)
        _eiis_v3_pointer_write ".cursor/rules/${name}.mdc" "$name" "$description" \
          "$root/PERSONA.md" "$root/SPEC.md"
        adapter_lines="${adapter_lines}pointer\t.cursor/rules/${name}.mdc\t$root/PERSONA.md\n"
        ;;
    esac
  done

  if [[ -f "$receipt" ]]; then
    local adapters='[]' tmp
    while IFS=$'\t' read -r type path canonical; do
      [[ -n "$type" ]] || continue
      case "$path" in
        .claude/*) host="claude-code" ;; .codex/*) host="codex" ;;
        .github/*) host="copilot" ;; .opencode/*) host="opencode" ;;
        .cursor/*) host="cursor" ;; *) host="raw" ;;
      esac
      adapters="$(printf '%s' "$adapters" | jq -c --arg h "$host" --arg p "$path" --arg t "$type" --arg c "$canonical" '. + [{host:$h,path:$p,type:$t,canonical:$c}]')"
    done <<EOF
$(printf '%b' "$adapter_lines")
EOF
    tmp="$(mktemp)"
    jq --argjson adapters "$adapters" '.adapters = $adapters' "$receipt" > "$tmp" && mv "$tmp" "$receipt"
  fi
}

eiis_v3_check_pointer() {
  local path="$1" canonical="$2"
  [[ -f "$path" ]] || return 1
  [[ "$(wc -c < "$path" | tr -d ' ')" -le "$EIIS_V3_POINTER_MAX_BYTES" ]] || return 1
  grep -qF 'generated_by: eidolons' "$path" || return 1
  grep -qF "$canonical" "$path" || return 1
  ! grep -qF '<!-- eidolon:' "$path"
}
