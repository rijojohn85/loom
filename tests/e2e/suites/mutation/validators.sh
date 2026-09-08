#!/usr/bin/env bash
# suites/mutation/validators.sh — validator functions shared by the offline
# suite and the mutation suite (sourced, never executed). Each v_* function
# prints the failure reason to stdout and returns 1 when the artifact under
# test FAILS validation ("the validator fired"), 0 when it passes. The
# mutation runner asserts firing + reason match; offline steps assert passing.
: "${E2E_ROOT:?}"

# ---- pure audits shared with offline steps (identical logic both sides)

v_duration() {  # <elapsed-s> <budget-s> — prints reason, 1 when over budget
  local elapsed="$1" budget="$2"
  if [[ "${elapsed}" -le "${budget}" ]]; then return 0; fi
  echo "offline suite took ${elapsed}s over the ${budget}s budget"
  return 1
}

v_verdict_scan() {  # <dir...> — prints offending lines, 1 when found
  local pat="pa""ss" bad
  bad="$(grep -rEwn --include='*.sh' -e "${pat}" "$@" 2>/dev/null \
    | grep -v 'offline-pass' | grep -v 'full-e2e-pass' \
    | grep -w "${pat}" | grep -v 'verdict.sh' || true)"
  if [[ -n "${bad}" ]]; then echo "${bad}"; return 1; fi
  return 0
}

v_claim_audit() {  # <checks.jsonl> <caps.jsonl> — 0 clean, 1 failed, 3 blocked-only
  local checks="$1" caps="$2" failed="" blocked=""
  while IFS= read -r outcome; do
    local cid h strong_total=0 blocked_cite="" n_cites=0 chk cstate strong
    cid="$(jq -r .capability_id <<<"${outcome}")"
    h="$(jq -r .harness <<<"${outcome}")"
    while IFS= read -r chk; do
      [[ -z "${chk}" ]] && continue
      n_cites=$((n_cites + 1))
      strong="$(jq -s --arg id "${chk}" \
        '[.[] | select(.id == $id and .state == "passed" and .pinned
          and (.claim_kind == "official-schema" or .claim_kind == "harness-loader-probe"
            or .claim_kind == "behaviour-probe"))] | length' "${checks}")"
      strong_total=$((strong_total + strong))
      if [[ "${strong}" -eq 0 ]]; then
        cstate="$(jq -s -r --arg id "${chk}" \
          '[.[] | select(.id == $id) | .state] | last // "MISSING"' "${checks}")"
        if [[ "${cstate}" == "blocked" || "${cstate}" == "MISSING" ]]; then
          blocked_cite="${chk} (${cstate})"
        fi
      fi
    done < <(jq -r '.checks[]' <<<"${outcome}")
    if [[ "${strong_total}" -eq 0 && "${n_cites}" -gt 0 ]]; then
      if [[ -n "${blocked_cite}" ]]; then
        [[ -z "${blocked}" ]] && blocked="${cid}/${h} cites ${blocked_cite}"
      else
        [[ -z "${failed}" ]] && failed="${cid}/${h} has no official-schema, harness-loader-probe or behaviour-probe evidence"
      fi
    fi
  done < <(jq -c -s '.[] | select(.state == "preserved" or .state == "verified-compensated")' "${caps}")
  if [[ -n "${failed}" ]]; then echo "FAILED:${failed}"; return 1; fi
  if [[ -n "${blocked}" ]]; then echo "BLOCKED:${blocked}"; return 3; fi
  return 0
}

# ---- artifact validators (mirror the offline steps on a workspace copy)

v_artifacts() {  # <ws>
  local ws="$1" rel
  while IFS= read -r rel; do
    [[ -z "${rel}" || "${rel}" == \#* ]] && continue
    [[ -f "${ws}/${rel}" ]] || { echo "expected artifact absent: ${rel}"; return 1; }
    "${E2E_ROOT}/tools/parse.py" "${ws}/${rel}" >/dev/null 2>&1 \
      || { echo "generated artifact does not parse: ${rel}"; return 1; }
    jq -e --arg p "${rel}" '.artifacts | map(.path) | index($p)' \
      "${E2E_ROOT}/oracle/expected-artifacts.json" >/dev/null \
      || { echo "unexpected file produced: ${rel}"; return 1; }
  done < "${ws}/agent/harness-specs/loom-manifest.txt"
  return 0
}

v_structural() {  # <ws>
  local ws="$1" f
  "${E2E_ROOT}/tools/parse.py" "${ws}/.codex/config.toml" >/dev/null 2>&1 \
    || { echo "codex adapter does not parse"; return 1; }
  for f in .devin/mcp_config.json .devin/config.json .devin/hooks.v1.json opencode.json; do
    "${E2E_ROOT}/tools/parse.py" "${ws}/${f}" >/dev/null 2>&1 \
      || { echo "adapter does not parse: ${f}"; return 1; }
  done
  return 0
}

v_schema() {  # <ws>
  local ws="$1" out code py=python3
  [[ -x "${E2E_ROOT}/.venv/bin/python" ]] && py="${E2E_ROOT}/.venv/bin/python"
  set +e
  out="$("${py}" "${E2E_ROOT}/tools/schema_validate.py" \
    "${E2E_ROOT}/schemas/opencode.config.schema.json" "${ws}/opencode.json" 2>&1)"
  code=$?
  set -e
  if [[ "${code}" -eq 0 ]]; then return 0; fi
  if [[ "${code}" -eq 3 ]]; then echo "schema validator blocked: ${out:0:120}"; return 1; fi
  echo "opencode.json fails official schema: ${out:0:200}"
  return 1
}

v_idempotence() {  # <ws>
  local ws="$1" d
  d="$(mktemp -d)"
  (cd "${ws}" && ./agent/tools/loom.sh >/dev/null 2>&1) \
    || { echo "regeneration failed"; rm -rf "${d}"; return 1; }
  (cd "${ws}" && find .codex .devin opencode.json agent/harness-specs/GAPS.md agent/harness-specs/loom-manifest.txt -type f -exec sha256sum {} + | LC_ALL=C sort) > "${d}/a"
  (cd "${ws}" && ./agent/tools/loom.sh >/dev/null 2>&1) \
    || { echo "regeneration failed"; rm -rf "${d}"; return 1; }
  (cd "${ws}" && find .codex .devin opencode.json agent/harness-specs/GAPS.md agent/harness-specs/loom-manifest.txt -type f -exec sha256sum {} + | LC_ALL=C sort) > "${d}/b"
  if cmp -s "${d}/a" "${d}/b"; then rm -rf "${d}"; return 0; fi
  rm -rf "${d}"
  echo "repeat generation from frozen inputs is not byte-identical"
  return 1
}

v_drift() {  # <ws> — --check must FAIL on the (already mutated) copy
  local ws="$1" out
  out="$(cd "${ws}" && ./agent/tools/loom.sh --check 2>&1 || true)"
  if grep -q "ORPHAN" <<<"${out}"; then echo "ORPHAN artifact reported"; return 1; fi
  if grep -q "MISSING" <<<"${out}"; then echo "MISSING artifact reported"; return 1; fi
  if grep -q "DRIFT" <<<"${out}"; then echo "DRIFT reported on hand-edited artifact"; return 1; fi
  if grep -q "FAILED" <<<"${out}"; then echo "--check FAILED as required (${out}  | head -1)"; return 1; fi
  echo "--check passed on mutated tree"
  return 0
}

v_loader_codex() {  # <ws> <url-a> <url-b>
  local ws="$1" a="$2" b="$3" out
  out="$(cd "${ws}" && run_isolated codex mcp list --json 2>&1)" || {
    echo "codex mcp list failed: $(head -1 <<<"${out}")"; return 1; }
  jq -e --arg a "${a}" --arg b "${b}" '
    (map(.name) | index("docs-a") and index("docs-b") and index("docs-local"))
    and ([.[] | select(.name == "docs-a") | .. | strings] | index($a))
    and ([.[] | select(.name == "docs-b") | .. | strings] | index($b))' \
    <<<"${out}" >/dev/null 2>&1 \
    || { echo "codex resolved an unexpected server set"; return 1; }
  return 0
}

v_loader_opencode() {  # <ws> <url-a> <url-b>
  local ws="$1" a="$2" b="$3" out
  out="$(cd "${ws}" && run_isolated opencode debug config 2>&1)" || {
    echo "opencode debug config failed: $(head -1 <<<"${out}")"; return 1; }
  jq -e --arg a "${a}" --arg b "${b}" '
    .mcp["docs-a"].url == $a and .mcp["docs-b"].url == $b
    and .mcp["docs-local"].url == "stdio://docs-local"' \
    <<<"${out}" >/dev/null 2>&1 \
    || { echo "opencode resolved config differs from emitted adapter"; return 1; }
  return 0
}

v_cap_gap() {  # <ws> <gap-id> — every dropped node must be in the copy GAPS.md
  local ws="$1" g="$2" node harness
  harness="$(jq -r --arg g "${g}" '.gaps[] | select(.gap_id == $g) | .harness' \
    "${E2E_ROOT}/oracle/approved-gaps.json")"
  while IFS= read -r node; do
    [[ -z "${node}" ]] && continue
    grep -Fq "| ${harness} | ${node} |" "${ws}/agent/harness-specs/GAPS.md" \
      || { echo "dropped node missing for ${g}: ${node}"; return 1; }
  done < <(jq -r --arg g "${g}" \
    '.gaps[] | select(.gap_id == $g) | .dropped_nodes[]?' \
    "${E2E_ROOT}/oracle/approved-gaps.json")
  return 0
}

v_cap_mcp() {  # <ws> <harness> <url-a> <url-b>
  local ws="$1" h="$2" a="$3" b="$4"
  case "${h}" in
    codex)
      "${E2E_ROOT}/tools/parse.py" "${ws}/.codex/config.toml" 2>/dev/null \
        | jq -e --arg a "${a}" --arg b "${b}" '
          .data.mcp_servers["docs-a"].url == $a
          and .data.mcp_servers["docs-b"].url == $b
          and .data.mcp_servers["docs-local"].url == "stdio://docs-local"' \
        >/dev/null || { echo "codex mcp capability failed"; return 1; } ;;
    opencode)
      jq -e --arg a "${a}" --arg b "${b}" '
        .mcp["docs-a"].url == $a and .mcp["docs-b"].url == $b' \
        "${ws}/opencode.json" >/dev/null \
        || { echo "opencode mcp capability failed"; return 1; } ;;
    *) echo "unknown harness ${h}"; return 2 ;;
  esac
  return 0
}

v_hook_order() {  # <ws> <manifest>
  local ws="$1" m="$2" want got
  want="$(jq -r '.expected_hook_order | join("\n")' "${m}" | sed 's|\$CLAUDE_PROJECT_DIR|$DEVIN_PROJECT_DIR|')"
  got="$(jq -r '.PreToolUse[0].hooks[].command' "${ws}/.devin/hooks.v1.json")"
  [[ "${want}" == "${got}" ]] || { echo "devin hook order differs from manifest"; return 1; }
  return 0
}

v_hook_escaping() {  # <ws> <manifest>
  local ws="$1" m="$2" want got
  want="$(jq -r .expected_hook_command "${m}" | sed 's|\$CLAUDE_PROJECT_DIR|$DEVIN_PROJECT_DIR|')"
  got="$(jq -r '.PreToolUse[0].hooks[0].command' "${ws}/.devin/hooks.v1.json")"
  [[ "${want}" == "${got}" ]] \
    || { echo "hook command not round-tripped byte-exactly"; return 1; }
  return 0
}

v_transport_override() {  # <ws> <url-b>
  local ws="$1" b="$2" got
  got="$(jq -r '.mcpServers["docs-b"].args[2] // empty' "${ws}/.devin/mcp_config.json")"
  [[ "${got}" == "${b}" ]] || { echo "devin bridge override missing"; return 1; }
  return 0
}

v_variant_servers() {  # <ws> <expected-csv>
  local ws="$1" want="$2" got
  got="$(jq -r '.mcpServers | keys | sort | join(",")' "${ws}/.devin/mcp_config.json")"
  [[ "${got}" == "${want}" ]] || { echo "unexpected server set: ${got} (want ${want})"; return 1; }
  return 0
}

v_variant_empty() {  # <ws>
  local ws="$1" got
  got="$(jq -r '.mcpServers | length' "${ws}/.devin/mcp_config.json")"
  [[ "${got}" == "0" ]] || { echo "expected zero servers, got ${got}"; return 1; }
  return 0
}

v_portability() {  # <ws-a> <ws-b> <resolved-input> — Stefan: no local values differ
  local a="$1" b="$2" res="$3" rel
  for rel in .codex/config.toml opencode.json .devin/mcp_config.json .devin/config.json .devin/hooks.v1.json agent/harness-specs/GAPS.md; do
    "${E2E_ROOT}/tools/compare.py" "${a}/${rel}" "${b}/${rel}" \
      --resolved-input "${res}" >/dev/null 2>&1 \
      || { echo "cross-workspace difference beyond ephemeral fields: ${rel}"; return 1; }
  done
  if grep -r "/tmp/loom-e2e-" "${a}/.codex" "${a}/.devin" "${a}/opencode.json" \
      "${a}/agent/harness-specs/GAPS.md" 2>/dev/null; then
    echo "absolute temporary path leaked into generated artifacts"
    return 1
  fi
  return 0
}

v_nonet() {  # <ws> <deny-cmd...> — the denial run must FAIL (attempt proven)
  local ws="$1"; shift
  "$@" bash -c "
    set -euo pipefail
    cd '${ws}' && ./agent/tools/loom.sh >/dev/null 2>&1
  " >/dev/null 2>&1 \
    && { echo "denial run succeeded despite planted network dependency"; return 0; }
  echo "network call observed under denial"
  return 1
}

v_generate_ok() {  # <ws> — generation must SUCCEED (validator fires when it fails)
  local ws="$1" out
  out="$(cd "${ws}" && ./agent/tools/loom.sh 2>&1)" || {
    echo "generation failed: $(head -1 <<<"${out}")"; return 1; }
  return 0
}

v_refusal() {  # <ws> <pattern> — generation must REFUSE with matching reason
  local ws="$1" pat="$2" out code
  set +e
  out="$(cd "${ws}" && ./agent/tools/loom.sh 2>&1)"; code=$?
  set -e
  if [[ "${code}" -eq 0 ]]; then echo "generation succeeded but must refuse"; return 0; fi
  grep -Eq "${pat}" <<<"${out}" \
    && { echo "refused as declared: $(grep -Eo "${pat}" <<<"${out}" | head -1)"; return 1; }
  echo "refused but reason did not match /${pat}/"
  return 0
}

v_docs_cover() {  # <help-file> <readme-file> — 0 when every flag/suite/exit/state documented
  local help="$1" readme="$2" missing="" flag suite code state
  for flag in --suite --full --harness --variant --keep --keep-on-failure \
               --clean --timeout --ceiling-usd --trials --pinned --advisory \
               --no-trust-seed --results-dir --bootstrap --list --help; do
    grep -qF -e "${flag}" "${help}" || missing="${missing} help:${flag}"
    grep -qF -e "${flag}" "${readme}" || missing="${missing} readme:${flag}"
  done
  for suite in offline mutation live conformance intent; do
    grep -qF -e "${suite}" "${help}" || missing="${missing} help:suite:${suite}"
    grep -qF -e "${suite}" "${readme}" || missing="${missing} readme:suite:${suite}"
  done
  for code in "| 0 |" "| 1 |" "| 2 |" "| 3 |" "| 4 |" "| 5 |"; do
    grep -qF -e "${code}" "${readme}" || missing="${missing} readme:exit${code}"
  done
  for state in passed failed approved-gap skipped blocked preserved \
               verified-compensated unverified; do
    grep -qF -e "${state}" "${readme}" || missing="${missing} readme:state:${state}"
  done
  if [[ -n "${missing}" ]]; then echo "undocumented runner surface:${missing}"; return 1; fi
  return 0
}
