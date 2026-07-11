# BPE-tolerance fixture (AC-D06)

Fixed English/code-mixed sample used to check that the `chars/4` proxy
stays within +/-15% of a real BPE tokenizer's count on realistic cortex
prose. The reference count below was recorded OFFLINE, once, via the
`cl100k_base` encoding (OpenAI `tiktoken`, the same family SPECTRA
targets in `roster/model-profiles.yaml` note); the bats test does NOT
call a live tokenizer — it diffs the recorded fixture numbers, which is
what AC-D06 explicitly requires ("recorded fixture comparison, not a
live BPE call").

Recorded reference (regenerate with:
`python3 -c "import tiktoken; print(len(tiktoken.get_encoding('cl100k_base').encode(open('/dev/stdin').read())))" < region.txt`
against the exact bytes between the markers below):

- sample_bytes (what `wc -c` / this script measures): 795
- cl100k_base_reference_tokens (measured on the decoded unicode text — one
  "—" em dash accounts for the 2-byte gap vs a 793-codepoint count): 184
- chars/4 proxy (ceil(795/4)): 199
- proxy/reference ratio: 199/184 = 1.0815 (within the +/-15% band: 0.85-1.15)

<!-- always-loaded:start -->
Add a `--json` flag to `cli/src/status.sh` and update
`cli/tests/status.bats` so the new case passes. The orchestrator
routes a localized, verifier-backed micro-task to the executor; the
executor patches an ephemeral sandbox, proves it externally with the
project's own test suite, and PROPOSEs a verified patch upward for the
orchestrator to apply. It never commits to the real tree and never
routes work onward — worker, never router. Refuses design, plan,
cross-cutting refactor, and any loop-native campaign; scores below tau
route to clarification_request with one to three targeted questions.
Same prompt, same context, same roster always yields the same routing
decision (I-C6). Bash 3.2 compatible: no associative arrays, no
${var,,} case conversion, no readarray, no &>> redirection.
<!-- always-loaded:end -->
