#!/usr/bin/env bash
# scripts/dispatch-predicate-extractor.sh — deterministic Step-2(a)/(b) signal
# extractor for the Gilgamesh fallthrough predicate.
#
# ESL change generalist-eidolon, Track C (R-017/R-018/R-049/R-054;
# AC-C05/AC-C06/AC-C09/AC-C10/AC-C11/AC-C12). Full rule + lexicon reference:
# `.spectra/changes/generalist-eidolon/acceptance-criteria.md` §"The reference
# extractor" (frozen, SHA-256 d088c0cc...) / `methodology/cortex/dispatch-predicate.md`
# (on-demand cortex copy).
#
# Presence-based, closed-lexicon, no LLM call, no eval (I-C2 analog for the
# cortex predicate layer). Two runs on the same prompt give the same vector
# by construction (I-C6).
#
# Usage:
#   dispatch-predicate-extractor.sh "<prompt text>"
#   dispatch-predicate-extractor.sh --verdict "<prompt text>"
#
# Output (stdout):
#   default    — five space-separated 0/1 values — "S1 S2 S3 S4 S5" — for
#                the given prompt, in that order. Nothing else is written.
#   --verdict  — a single token, "actionable" or "clarify": the frozen
#                combinator S1∧S2∧S3∧S4∧S5 evaluated over the computed
#                vector (S6/S7 are preconditions from the Step-1 scorer —
#                the caller, e.g. cli/src/run.sh, only invokes --verdict
#                once it has already established S6∧S7 by construction, so
#                this mode does not re-derive them). This is the single
#                source of truth for the boolean the kernel dispatches
#                on — callers MUST reuse this mode rather than
#                re-implementing the combinator (see
#                scripts/dispatch-predicate-selfcheck.sh for the
#                independent re-derivation used by the fixture self-check).
#
# Exit codes:
#   0 — vector/verdict computed and printed
#   2 — usage error (no prompt argument)
#
# Implementation note — phrase pre-normalization: rather than a raw-string
# gsub (which mis-boundaries on sentence-final punctuation, e.g. "the
# project." with no space between the phrase and the period), this
# tokenizes first and merges ADJACENT TOKEN CORES (post edge-punctuation
# strip) pairwise against the closed phrase list. This is semantically
# equivalent to the frozen "phrase pre-normalization" pass but robust to
# trailing punctuation.
#
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile, no
# &>>. The heavy lifting runs in a single awk BEGIN block (POSIX awk arrays
# are not the bash-3.2-restricted "declare -A" construct — this mirrors the
# existing repo pattern of a bash-3.2-safe outer harness driving a jq/awk
# computation, e.g. cli/src/run.sh).
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

VERDICT_MODE=0
if [ "$#" -ge 1 ] && [ "$1" = "--verdict" ]; then
  VERDICT_MODE=1
  shift
fi

if [ "$#" -lt 1 ]; then
  printf 'Usage: %s [--verdict] "<prompt text>"\n' "$(basename "$0")" >&2
  exit 2
fi

PROMPT="$1"

awk -v prompt="$PROMPT" -v verdict_mode="$VERDICT_MODE" '
function strip_lead_trail(s,    changed, c) {
  changed = 1
  while (changed == 1 && length(s) > 0) {
    changed = 0
    c = substr(s, length(s), 1)
    if (c == "," || c == ";" || c == ":" || c == "." || c == "!" || c == "?" || \
        c == ")" || c == "]" || c == "}" || c == "\x27" || c == "\"") {
      s = substr(s, 1, length(s) - 1)
      changed = 1
    }
  }
  changed = 1
  while (changed == 1 && length(s) > 0) {
    changed = 0
    c = substr(s, 1, 1)
    if (c == "(" || c == "[" || c == "{" || c == "\x27" || c == "\"") {
      s = substr(s, 2)
      changed = 1
    }
  }
  return s
}

function is_fenced(s) {
  return (length(s) >= 2 && substr(s, 1, 1) == "`" && substr(s, length(s), 1) == "`")
}

function strip_backticks(s) {
  if (is_fenced(s)) {
    return substr(s, 2, length(s) - 2)
  }
  return s
}

# core() = strip surrounding backticks + edge punctuation, per
# acceptance-criteria.md "PATH_OR_ID token" §preamble ("evaluated on the
# token core = strip surrounding backticks + edge punctuation").
function core_of(raw) {
  return strip_backticks(strip_lead_trail(raw))
}

function in_list(key, list_str,    i, n, arr) {
  n = split(list_str, arr, "\n")
  for (i = 1; i <= n; i++) {
    if (arr[i] == key) return 1
  }
  return 0
}

# Closed 2-word phrase table. Returns the normalized underscore-joined
# token, or "" if (c1, c2) is not a recognized phrase pair.
function phrase_merge(c1, c2) {
  if (c1 == "set"     && c2 == "up")       return "set_up"
  if (c1 == "look"     && c2 == "into")    return "look_into"
  if (c1 == "figure"   && c2 == "out")     return "figure_out"
  if (c1 == "look"     && c2 == "at")      return "look_at"
  if (c1 == "deal"     && c2 == "with")    return "deal_with"
  if (c1 == "work"     && c2 == "on")      return "work_on"
  if (c1 == "roll"     && c2 == "back")    return "roll_back"
  if (c1 == "limited"  && c2 == "to")      return "limited_to"
  if (c1 == "so"       && c2 == "that")    return "so_that"
  if (c1 == "exits"    && c2 == "0")       return "exits_0"
  if (c1 == "without"  && c2 == "error")   return "without_error"
  if (c1 == "no"       && c2 == "longer")  return "no_longer"
  if (c1 == "entire"   && c2 == "codebase") return "entire_codebase"
  if (c1 == "the"      && c2 == "project") return "the_project"
  if (c1 == "the"      && c2 == "codebase") return "the_codebase"
  if (c1 == "the"      && c2 == "app")     return "the_app"
  if (c1 == "the"      && c2 == "repo")    return "the_repo"
  if (c1 == "the"      && c2 == "system")  return "the_system"
  return ""
}

# PATH_OR_ID per acceptance-criteria.md "PATH_OR_ID token (tightened)".
# Operates on a raw (unmerged) token; phrase-merged tokens are never paths.
function is_path_or_id(raw,    edge_stripped, fenced, core, has_letter, dot_pos, stem, ext, i, ch) {
  edge_stripped = strip_lead_trail(raw)
  fenced = is_fenced(edge_stripped)
  core = strip_backticks(edge_stripped)

  # Rule 1 — path: contains "/" and contains >=1 letter.
  if (index(core, "/") > 0) {
    has_letter = 0
    for (i = 1; i <= length(core); i++) {
      ch = substr(core, i, 1)
      if (ch ~ /[a-z]/) { has_letter = 1; break }
    }
    if (has_letter) return 1
  }

  # Rule 2 — known extension: stem contains a letter, ext in FILE_EXT.
  dot_pos = 0
  for (i = length(core); i >= 1; i--) {
    if (substr(core, i, 1) == ".") { dot_pos = i; break }
  }
  if (dot_pos > 0 && dot_pos < length(core)) {
    stem = substr(core, 1, dot_pos - 1)
    ext = substr(core, dot_pos + 1)
    if (stem ~ /^[A-Za-z0-9_.-]*$/ && ext ~ /^[A-Za-z0-9]+$/) {
      has_letter = 0
      for (i = 1; i <= length(stem); i++) {
        ch = substr(stem, i, 1)
        if (ch ~ /[a-z]/) { has_letter = 1; break }
      }
      if (has_letter && in_list(ext, FILE_EXT)) return 1
    }
  }

  # Rule 3 — fenced identifier.
  if (fenced && core ~ /^(--)?[a-z_][a-z0-9_-]*$/) return 1

  return 0
}

BEGIN {
  ACT_VERBS = "add\ncreate\nwrite\nimplement\nbuild\nfix\nedit\nmodify\nupdate\nrename\nremove\ndelete\nrefactor\nmigrate\nconfigure\nwire\ninstall\ngenerate\napply\npatch\nreplace\nextend\nrewrite\nconvert\nbump\nupgrade\nset_up\nscaffold\nappend\ninsert\nenable\ndisable\nrevert\nrollback\nroll_back\nseed\nprovision\ncompile\nlint\nformat\nexport\nimport\npublish\ninit\nbootstrap\nstub\ndeprecate"
  EXCLUDED_POLYSEMOUS = "make\nimprove\nhandle\ndeal_with\nwork_on\nbetter"
  DELIVERABLE_NOUNS = "file\npatch\nfunction\nmethod\nclass\nmodule\nendpoint\nroute\nscript\nconfig\ntest\nfixture\nmigration\nworkflow\nschema\ntable\ncomponent\nflag\ncli\nci\npipeline\ndockerfile\nreadme\ndocs\nhook\nrule\nfield"
  GENERIC_SCOPE = "everything\neverywhere\nall\nentire\nwhole\nproject_wide\nrepo_wide\ncodebase\nthroughout\nacross\nanything\nsomewhere\nthe_project\nthe_codebase\nthe_app\nthe_repo\nthe_system\nentire_codebase"
  LIMITERS = "only\njust\nlimited_to\nsolely\nexclusively"
  ACCEPTANCE_MARKERS = "so_that\nuntil\npasses\npassing\nmatches\nreturns\nexpected\nequal\ngreen\nexits_0\nwithout_error\nno_longer\nfixes"
  FILE_EXT = "ts\ntsx\njs\njsx\npy\nrb\ngo\nrs\nsh\nbash\njson\nyaml\nyml\ntoml\nmd\ntxt\nsql\nbats\njava\nkt\nc\nh\ncpp\ncs\nphp\nlock\ncfg\nini\nenv"
  CLAUSE_MARKERS = "and\nthen\nalso\nto\nplease"
  DET_BLOCKLIST = "the\na\nan\nthis\nthat\nthese\nthose\nmy\nour\nyour\nhis\nher\nits\ntheir\nno\nany\nsome\neach\nevery"

  txt = tolower(prompt)
  n = split(txt, raw_toks, " ")

  # Pass 1: per-token core (edge-punctuation + backtick stripped).
  m = 0
  for (i = 1; i <= n; i++) {
    if (raw_toks[i] == "") continue
    m++
    r[m] = raw_toks[i]
    cr[m] = core_of(raw_toks[i])
  }

  # Pass 2: merge adjacent CLOSED 2-word phrases (robust to trailing
  # sentence punctuation on the second word, since we compare CORES).
  k = 0
  i = 1
  while (i <= m) {
    merged = ""
    if (i < m) merged = phrase_merge(cr[i], cr[i + 1])
    if (merged != "") {
      k++
      eff_core[k] = merged
      eff_raw[k] = ""        # a phrase-merged token is never a PATH_OR_ID candidate
      eff_last_raw[k] = r[i + 1]  # trailing-punctuation source = the 2nd raw word
      i += 2
    } else {
      k++
      eff_core[k] = cr[i]
      eff_raw[k] = r[i]
      eff_last_raw[k] = r[i]
      i += 1
    }
  }

  s1 = 0; s2 = 0; s3 = 0; s4 = 0; s5 = 0
  has_generic_scope = 0
  has_limiter = 0
  has_path_or_id = 0

  for (j = 1; j <= k; j++) {
    c = eff_core[j]

    # S1 — act_verb, imperative position, DET_BLOCKLIST noun guard.
    if (in_list(c, ACT_VERBS) && !in_list(c, EXCLUDED_POLYSEMOUS)) {
      if (j == 1) {
        s1 = 1
      } else {
        prev_core = eff_core[j - 1]
        prev_last_raw = eff_last_raw[j - 1]
        prev_is_clause_marker = 0
        if (in_list(prev_core, CLAUSE_MARKERS)) prev_is_clause_marker = 1
        if (length(prev_last_raw) > 0) {
          lastc = substr(prev_last_raw, length(prev_last_raw), 1)
          if (lastc == "," || lastc == ";" || lastc == ":" || lastc == ".") prev_is_clause_marker = 1
        }
        if (prev_is_clause_marker && !in_list(prev_core, DET_BLOCKLIST)) {
          s1 = 1
        }
      }
    }

    # S2 deliverable input.
    if (in_list(c, DELIVERABLE_NOUNS)) s2 = 1

    # S3 named_target input (only meaningful for unmerged raw tokens).
    if (eff_raw[j] != "" && is_path_or_id(eff_raw[j])) { s3 = 1; has_path_or_id = 1 }

    # S4 acceptance: closed marker OR numeric target (%-suffixed or
    # immediately followed by a word token).
    if (in_list(c, ACCEPTANCE_MARKERS)) s4 = 1
    if (c ~ /^[0-9]+%?$/) {
      if (c ~ /%$/) {
        s4 = 1
      } else if (j < k && eff_core[j + 1] != "" && eff_core[j + 1] ~ /^[a-z]/) {
        s4 = 1
      }
    }

    # S5 inputs.
    if (in_list(c, GENERIC_SCOPE)) has_generic_scope = 1
    if (in_list(c, LIMITERS)) has_limiter = 1
  }

  if (has_path_or_id) s2 = 1  # S2 = deliverable OR path
  if (has_generic_scope) {
    s5 = (has_limiter && has_path_or_id) ? 1 : 0
  } else {
    s5 = 1
  }

  if (verdict_mode == 1) {
    # Frozen combinator (acceptance-criteria.md "Predicate"): only evaluated
    # by the caller once S6∧S7 already hold — see the --verdict usage note.
    if (s1 == 1 && s2 == 1 && s3 == 1 && s4 == 1 && s5 == 1) {
      print "actionable"
    } else {
      print "clarify"
    }
  } else {
    print s1, s2, s3, s4, s5
  }
}
'
