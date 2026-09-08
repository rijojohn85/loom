#!/usr/bin/env bash
# suites/mutation/run.sh — planted-defect self-verification (T053, T056, T058, T059).
#
# Applies each registry entry to a throwaway copy, runs only the owning
# validator, and asserts both the failure and that the recorded reason
# matches expected_reason_pattern. A mutation the validator does not catch,
# or catches for the wrong reason, fails the mutation check — a green offline
# run means something only because this suite goes red on demand.
# Every mutation check carries mutation_id per the results schema (T059).
set -euo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export E2E_ROOT
: "${E2E_RUN_DIR:?}"
REPO_ROOT="$(cd "${E2E_ROOT}/../.." && pwd)"
export REPO_ROOT

# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/workspace.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/isolate.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/trust.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/install.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/offline/materialize.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/mutation/validators.sh"

MUT="${E2E_RUN_DIR}/mutation"
mkdir -p "${MUT}"

registry_pattern() {  # <registry-id> -> expected_reason_pattern
  jq -r --arg id "$1" '.mutations[] | select(.id == $id) | .expected_reason_pattern' \
    "${E2E_ROOT}/oracle/mutations.json"
}
registry_validator() {  # <registry-id> -> expected_failing_validator
  jq -r --arg id "$1" '.mutations[] | select(.id == $id) | .expected_failing_validator' \
    "${E2E_ROOT}/oracle/mutations.json"
}

# mutation_done <registry-id> <validator> <fire:0|1> <reason>
# fire=1 means the owning validator failed (fired) with <reason>.
mutation_done() {
  local rid="$1" validator="$2" fire="$3" reason="$4"
  local suffix="${rid#mutation.}"
  local pattern
  pattern="$(registry_pattern "${rid}")"
  if [[ "${fire}" == "1" ]] && grep -Eq "${pattern}" <<<"${reason}"; then
    record_check id="mutation.${suffix}" suite=mutation mandatory=true \
      state=passed claim_kind=behaviour-probe mutation_id="${rid}" \
      evidence="mutation/${suffix}.log" \
      reason="validator ${validator} failed as declared"
  elif [[ "${fire}" == "1" ]]; then
    record_check id="mutation.${suffix}" suite=mutation mandatory=true \
      state=failed claim_kind=behaviour-probe mutation_id="${rid}" \
      reason="validator ${validator} failed for the wrong reason: ${reason:0:200} (want /${pattern}/)"
  else
    record_check id="mutation.${suffix}" suite=mutation mandatory=true \
      state=failed claim_kind=behaviour-probe mutation_id="${rid}" \
      reason="planted defect not detected by ${validator}"
  fi
  echo "${reason}" > "${MUT}/${suffix}.log"
}

# fresh_copy <tag> -> path (throwaway copy of the golden workspace)
fresh_copy() {
  local dest="${MUT}/ws-$1"
  rm -rf "${dest}"
  cp -a "${GOLDEN_WS}" "${dest}"
  echo "${dest}"
}

# build_variant_ws <variant> <tag> -> path (own install+materialize+generate)
build_variant_ws() {
  local variant="$1" tag="$2" ws
  make_workspace "${E2E_ROOT}/fixtures/complete-claude" >/dev/null
  ws="${E2E_WORKSPACE}"
  export E2E_WORKSPACE="${ws}"
  install_loom "${ws}" "${MUT}/${tag}-install.log" >/dev/null 2>&1
  materialize_variant "${variant}" "${ws}" "${MUT}/${tag}-state" >/dev/null 2>&1
  seed_trust "${ws}" docs-a docs-b docs-local >/dev/null 2>&1 || true
  (cd "${ws}" && ./agent/tools/loom.sh >"${MUT}/${tag}-generate.log" 2>&1) || true
  export E2E_WORKSPACE="${GOLDEN_WS}"
  echo "${ws}"
}

# ---- T058: isolation digests before
FIX_BEFORE="$("${E2E_ROOT}/tools/digest.py" "${E2E_ROOT}/fixtures")"
REPO_BEFORE="$("${E2E_ROOT}/tools/digest.py" "${REPO_ROOT}/loom.sh" \
  "${REPO_ROOT}/lib" "${REPO_ROOT}/install.sh" \
  "${REPO_ROOT}/skills" "${REPO_ROOT}/harness-specs" | sha256sum | awk '{print $1}')"

# ---- golden base workspace (independent of any offline run)
make_workspace "${E2E_ROOT}/fixtures/complete-claude"
GOLDEN_WS="${E2E_WORKSPACE}"
isolate_env
export E2E_WORKSPACE="${GOLDEN_WS}"
install_loom "${GOLDEN_WS}" "${MUT}/golden-install.log" >/dev/null 2>&1 \
  || { record_check id=mutation.setup suite=mutation mandatory=true state=failed \
         reason="golden install failed" claim_kind=none mutation_id="mutation.setup"; exit 0; }
materialize_variant "base" "${GOLDEN_WS}" "${MUT}/golden-state" >/dev/null 2>&1
seed_trust "${GOLDEN_WS}" docs-a docs-b docs-local
(cd "${GOLDEN_WS}" && ./agent/tools/loom.sh >"${MUT}/golden-generate.log" 2>&1) \
  || { record_check id=mutation.setup suite=mutation mandatory=true state=failed \
         reason="golden generation failed" claim_kind=none mutation_id="mutation.setup"; exit 0; }
URL_A="$(jq -r .mcp_urls.docs_a "${MUT}/golden-state/resolved-input.json")"
URL_B="$(jq -r .mcp_urls.docs_b "${MUT}/golden-state/resolved-input.json")"
export GOLDEN_WS URL_A URL_B MUT

run_case() {  # <registry-id>
  local rid="$1" validator reason fire=0 ws
  validator="$(registry_validator "${rid}")"
  case "${rid}" in
    mutation.weaken-deny)
      ws="$(fresh_copy weaken-deny)"
      jq 'del(.permissions.deny[] | select(. == "Bash(rm -rf /)"))' \
        "${ws}/.claude/settings.json" > "${ws}/settings.json.tmp" \
        && mv "${ws}/settings.json.tmp" "${ws}/.claude/settings.json"
      (cd "${ws}" && ./agent/tools/loom.sh >/dev/null 2>&1)
      reason="$(v_cap_gap "${ws}" gap.codex.deny-rmrf)" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.drop-hook-order)
      ws="$(build_variant_ws hook-ordering drop-hook)"
      jq '.hooks.PreToolUse[0].hooks |= reverse' \
        "${ws}/.claude/settings.json" > "${ws}/settings.json.tmp" \
        && mv "${ws}/settings.json.tmp" "${ws}/.claude/settings.json"
      (cd "${ws}" && ./agent/tools/loom.sh >/dev/null 2>&1)
      reason="$(v_hook_order "${ws}" "${E2E_ROOT}/fixtures/variants/hook-ordering/manifest.json")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.change-endpoint-codex)
      ws="$(fresh_copy endpoint-codex)"
      sed -i "s|${URL_A}|https://evil.example/mcp|" "${ws}/.codex/config.toml"
      seed_trust "${ws}" docs-a docs-b docs-local >/dev/null 2>&1 || true
      reason="$(v_loader_codex "${ws}" "${URL_A}" "${URL_B}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.change-endpoint-opencode)
      ws="$(fresh_copy endpoint-opencode)"
      jq --arg u "https://evil.example/mcp" '.mcp["docs-a"].url = $u' \
        "${ws}/opencode.json" > "${ws}/opencode.json.tmp" \
        && mv "${ws}/opencode.json.tmp" "${ws}/opencode.json"
      seed_trust "${ws}" docs-a docs-b docs-local >/dev/null 2>&1 || true
      reason="$(v_loader_opencode "${ws}" "${URL_A}" "${URL_B}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.omit-artifact)
      ws="$(fresh_copy omit)"
      rm "${ws}/.devin/config.json"
      reason="$(v_artifacts "${ws}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.corrupt-schema-field)
      ws="$(fresh_copy corrupt-schema)"
      jq '.mcpX = .mcp | del(.mcp)' "${ws}/opencode.json" > "${ws}/opencode.json.tmp" \
        && mv "${ws}/opencode.json.tmp" "${ws}/opencode.json"
      reason="$(v_schema "${ws}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.corrupt-codex-toml)
      ws="$(fresh_copy corrupt-toml)"
      printf '\n[[[invalid toml\n' >> "${ws}/.codex/config.toml"
      reason="$(v_structural "${ws}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.hand-edit|mutation.delete-artifact|mutation.orphan-artifact)
      ws="$(fresh_copy drift)"
      case "${rid}" in
        mutation.hand-edit)
          jq '.mcp["docs-a"].url = "https://evil.example"' "${ws}/opencode.json" > "${ws}/opencode.json.tmp" \
            && mv "${ws}/opencode.json.tmp" "${ws}/opencode.json" ;;
        mutation.delete-artifact) rm "${ws}/.devin/hooks.v1.json" ;;
        mutation.orphan-artifact)
          echo "docs/stray.md" >> "${ws}/agent/harness-specs/loom-manifest.txt"
          mkdir -p "${ws}/docs" && echo stray > "${ws}/docs/stray.md" ;;
      esac
      reason="$(v_drift "${ws}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.unapproved-name)
      ws="$(build_variant_ws negative-unapproved-name unapproved)"
      # Insert INSIDE the Approved-servers table (before the next ## header):
      # appending at EOF would land outside the parsed table.
      sed -i 's@^## Notes$@| docs-evil | `https://evil.example/mcp` | read-only |\n\n## Notes@' \
        "${ws}/agent/policies/allowed-mcp-servers.md"
      if (cd "${ws}" && ./agent/tools/loom.sh >/dev/null 2>&1); then
        fire=1; reason="generation succeeded but must refuse"
      else
        fire=0; reason="generation still refused"
      fi
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason}" ;;
    mutation.invalid-input-fixed)
      ws="$(build_variant_ws negative-invalid-input invalidfixed)"
      # Rebuild a VALID .mcp.json with THIS workspace's URLs (golden's URLs
      # would mismatch this workspace's allowlist and refuse for the wrong reason).
      ua="$(jq -r .mcp_urls.docs_a "${MUT}/invalidfixed-state/resolved-input.json")"
      ub="$(jq -r .mcp_urls.docs_b "${MUT}/invalidfixed-state/resolved-input.json")"
      jq -n --arg a "${ua}" --arg b "${ub}" \
        '{mcpServers: {"docs-a": {type: "http", url: $a}, "docs-b": {type: "http", url: $b}}}' \
        > "${ws}/.mcp.json"
      if (cd "${ws}" && ./agent/tools/loom.sh >/dev/null 2>&1); then
        fire=1; reason="generation succeeded but must refuse"
      else
        fire=0; reason="generation still refused"
      fi
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason}" ;;
    mutation.url-now-provided)
      ws="$(build_variant_ws negative-url-less urlfixed)"
      jq '.mcpServers["docs-nourl"] = {type: "http", url: "https://nourl.example/mcp"}' \
        "${ws}/.mcp.json" > "${ws}/.mcp.json.tmp" && mv "${ws}/.mcp.json.tmp" "${ws}/.mcp.json"
      sed -i 's@^## Notes$@| docs-nourl | `https://nourl.example/mcp` | read-only |\n\n## Notes@' \
        "${ws}/agent/policies/allowed-mcp-servers.md"
      if (cd "${ws}" && ./agent/tools/loom.sh >/dev/null 2>&1); then
        fire=1; reason="generation succeeded but must refuse"
      else
        fire=0; reason="generation still refused"
      fi
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason}" ;;
    mutation.endpoint-now-approved)
      ws="$(build_variant_ws negative-unapproved-endpoint endpointfixed)"
      # Align with THIS workspace's URLs (golden's URLs would mismatch this
      # workspace's allowlist and refuse for the wrong reason).
      wurl_a="$(jq -r .mcp_urls.docs_a "${MUT}/endpointfixed-state/resolved-input.json")"
      sed -i "s|https://a.example/other|${wurl_a}|g" "${ws}/.mcp.json"
      if (cd "${ws}" && ./agent/tools/loom.sh >/dev/null 2>&1); then
        fire=1; reason="generation succeeded but must refuse"
      else
        fire=0; reason="generation still refused"
      fi
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason}" ;;
    mutation.nondeterministic-emitter)
      ws="$(fresh_copy nondeterm)"
      # Wrap the installed emitter (appending at file scope would run at
      # source time under set -u and crash collection instead): rename the
      # original, then append a wrapper that timestamps one output file.
      sed -i 's/^emit_devin() {/emit_devin_orig() {/' \
        "${ws}/agent/tools/lib/emit-devin.sh"
      printf '\nemit_devin() {\n  emit_devin_orig "$1" "$2"\n  echo "# generated at $(date +%%s%%N)" >> "$2/.devin/config.json"\n}\n' \
        >> "${ws}/agent/tools/lib/emit-devin.sh"
      reason="$(v_idempotence "${ws}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.leak-absolute-path)
      ws="$(fresh_copy leak)"
      echo "# /tmp/loom-e2e-FAKE-LEAK" >> "${ws}/opencode.json"
      reason="$(v_portability "${ws}" "${GOLDEN_WS}" "${MUT}/golden-state/resolved-input.json")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.drop-gap-row)
      ws="$(fresh_copy gaprow)"
      sed -i '/| devin | permission deny: Bash(rm -rf \/) |/d' "${ws}/agent/harness-specs/GAPS.md"
      reason="$(v_cap_gap "${ws}" gap.devin.deny-rmrf)" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.remove-opencode-server)
      ws="$(fresh_copy rmserver)"
      jq 'del(.mcp["docs-b"])' "${ws}/opencode.json" > "${ws}/opencode.json.tmp" \
        && mv "${ws}/opencode.json.tmp" "${ws}/opencode.json"
      reason="$(v_cap_mcp "${ws}" opencode "${URL_A}" "${URL_B}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.weaken-codex-expectation)
      ws="$(fresh_copy weakencodex)"
      sed -i '/\[mcp_servers."docs-b"\]/,/^$/d' "${ws}/.codex/config.toml"
      reason="$(v_cap_mcp "${ws}" codex "${URL_A}" "${URL_B}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.break-hook-command)
      ws="$(build_variant_ws paths-with-spaces-and-escaping breakhook)"
      jq '.PreToolUse[0].hooks[0].command += " --extra"' \
        "${ws}/.devin/hooks.v1.json" > "${ws}/hooks.json.tmp" \
        && mv "${ws}/hooks.json.tmp" "${ws}/.devin/hooks.v1.json"
      reason="$(v_hook_escaping "${ws}" "${E2E_ROOT}/fixtures/variants/paths-with-spaces-and-escaping/manifest.json")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.drop-bridge-override)
      ws="$(build_variant_ws transport-override dropbridge)"
      jq 'del(.mcp_overrides.devin["docs-b"])' \
        "${ws}/agent/tools/loom.config.json" > "${ws}/loom.config.tmp" \
        && mv "${ws}/loom.config.tmp" "${ws}/agent/tools/loom.config.json"
      (cd "${ws}" && ./agent/tools/loom.sh >/dev/null 2>&1)
      reason="$(v_transport_override "${ws}" "${URL_B}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.remove-http-server)
      ws="$(build_variant_ws http-only rmhttp)"
      jq 'del(.mcpServers["docs-b"])' \
        "${ws}/.devin/mcp_config.json" > "${ws}/mcp.json.tmp" \
        && mv "${ws}/mcp.json.tmp" "${ws}/.devin/mcp_config.json"
      reason="$(v_variant_servers "${ws}" "docs-a,docs-b")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.add-server-to-empty)
      ws="$(build_variant_ws empty-configuration addempty)"
      jq '.mcpServers["docs-x"] = {url: "https://x.example/mcp", transport: "http"}' \
        "${ws}/.devin/mcp_config.json" > "${ws}/mcp.json.tmp" \
        && mv "${ws}/mcp.json.tmp" "${ws}/.devin/mcp_config.json"
      reason="$(v_variant_empty "${ws}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.break-generation)
      ws="$(fresh_copy breakgen)"
      printf '\nexit 1\n' >> "${ws}/agent/tools/loom.sh"
      reason="$(v_generate_ok "${ws}")" && fire=0 || fire=1
      rm -rf "${ws}"
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.smoke-env)
      mkdir -p "${MUT}/fakebin"
      printf '#!/usr/bin/env bash\necho "fake jq: broken" >&2\nexit 1\n' > "${MUT}/fakebin/jq"
      chmod +x "${MUT}/fakebin/jq"
      if PATH="${MUT}/fakebin:${PATH}" "${REPO_ROOT}/tests/smoke.sh" >/dev/null 2>&1; then
        fire=0; reason="smoke passed with broken jq"
      else
        fire=1; reason="smoke.sh reported failures with broken jq"
      fi
      mutation_done "${rid}" "${validator}" "${fire}" "${reason}" ;;
    mutation.budget-exceeded)
      reason="$(v_duration 99999 180)" && fire=0 || fire=1
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-ok}" ;;
    mutation.unqualified-pass)
      mkdir -p "${MUT}/poison"
      printf '#!/usr/bin/env bash\necho "all checks pass"\n' > "${MUT}/poison/guard.sh"
      reason="$(v_verdict_scan "${MUT}/poison")" && fire=0 || fire=1
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-unqualified success token flagged}" ;;
    mutation.undocumented-flag)
      "${E2E_ROOT}/run.sh" --help > "${MUT}/help-full.txt"
      grep -v -e "--ceiling-usd" "${MUT}/help-full.txt" > "${MUT}/help-stripped.txt"
      reason="$(v_docs_cover "${MUT}/help-stripped.txt" "${E2E_ROOT}/README.md")" && fire=0 || fire=1
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-audit clean}" ;;
    mutation.drop-evidence-citation)
      cp "${E2E_RUN_DIR}/checks.jsonl" "${MUT}/checks-copy.jsonl" 2>/dev/null || echo '{"id":"none"}' > "${MUT}/checks-copy.jsonl"
      cp "${E2E_RUN_DIR}/capabilities.jsonl" "${MUT}/caps-copy.jsonl" 2>/dev/null || echo '{}' > "${MUT}/caps-copy.jsonl"
      if [[ "$(jq -s '[.[] | select(.id == "offline.loader.codex")] | length' "${MUT}/checks-copy.jsonl")" -gt 0 ]]; then
        jq -s 'map(if .id == "offline.loader.codex" then .claim_kind = "local-structural" else . end) | .[]' \
          "${MUT}/checks-copy.jsonl" > "${MUT}/checks-downgraded.jsonl"
        set +e
        reason="$(v_claim_audit "${MUT}/checks-downgraded.jsonl" "${MUT}/caps-copy.jsonl")"
        code=$?
        set -e
      else
        # Offline did not run in this invocation: synthesize the audit input.
        printf '{"id":"offline.loader.codex","suite":"offline","mandatory":true,"state":"passed","claim_kind":"local-structural","pinned":true,"attempts":[{"n":1,"state":"passed"}],"evidence":[],"duration_ms":0}\n' > "${MUT}/checks-downgraded.jsonl"
        printf '{"capability_id":"mcp.http.docs-a","harness":"codex","state":"preserved","evidence":[],"checks":["offline.loader.codex"]}\n' > "${MUT}/caps-copy.jsonl"
        set +e
        reason="$(v_claim_audit "${MUT}/checks-downgraded.jsonl" "${MUT}/caps-copy.jsonl")"
        code=$?
        set -e
      fi
      if [[ "${code}" -eq 1 ]]; then fire=1; else fire=0; fi
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-audit clean}" ;;
    mutation.phone-home-emitter)
      svc_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
      svc_audit="${MUT}/phone-home-audit.log"
      : > "${svc_audit}"
      python3 "${E2E_ROOT}/fixtures/services/mcp_http.py" "${svc_port}" "${svc_audit}" &
      svc_pid=$!
      register_child_pid "${svc_pid}"
      sleep 1
      ws="$(fresh_copy phonehome)"
      printf '\npage="$(curl -m 5 -sf http://127.0.0.1:%s/mcp -d "{}" || exit 1)"\n' "${svc_port}" \
        >> "${ws}/agent/tools/lib/emit-devin.sh"
      deny=()
      if unshare -n true 2>/dev/null; then
        deny=(unshare -n)
      elif unshare -rn true 2>/dev/null; then
        deny=(unshare -rn)
      else
        deny=(bwrap --unshare-net --bind / / --dev /dev --proc /proc)
      fi
      reason="$(v_nonet "${ws}" "${deny[@]}")" && fire=0 || fire=1
      rm -rf "${ws}"
      kill "${svc_pid}" 2>/dev/null || true
      mutation_done "${rid}" "${validator}" "${fire}" "${reason:-denial clean}" ;;
    mutation.oracle-tamper)
      "${E2E_ROOT}/suites/mutation/oracle-tamper.sh" || true ;;
    mutation.partial-overwrite)
      "${E2E_ROOT}/suites/mutation/partial-write.sh" || true ;;
    *) echo "mutation: unknown case ${rid}" >&2 ;;
  esac
}

while IFS= read -r rid; do
  [[ -z "${rid}" ]] && continue
  run_case "${rid}" || true
done < <(jq -r '.mutations[].id' "${E2E_ROOT}/oracle/mutations.json")

# ---- T056: every offline validator id is proven by at least one case
REQUIRED_OFFLINE="offline.smoke offline.artifacts offline.structural offline.schema
  offline.idempotence offline.portability offline.drift
  offline.negative.url-less offline.negative.unapproved-name
  offline.negative.unapproved-endpoint offline.negative.invalid-input
  offline.negative.partial-write offline.loader.codex offline.loader.opencode
  offline.capabilities.codex offline.capabilities.opencode offline.capabilities.devin
  offline.claim-kinds offline.variant.base offline.variant.hook-ordering
  offline.variant.paths-with-spaces-and-escaping offline.variant.transport-override
  offline.variant.http-only offline.variant.empty-configuration
  offline.duration offline.no-network offline.verdict-guard offline.docs"
missing=""
for vid in ${REQUIRED_OFFLINE}; do
  jq -e --arg v "${vid}" \
    '[.mutations[] | select(.expected_failing_validator == $v)] | length > 0' \
    "${E2E_ROOT}/oracle/mutations.json" >/dev/null \
    || missing="${missing} ${vid}"
done
if [[ -z "${missing}" ]]; then
  record_check id=mutation.coverage suite=mutation mandatory=true state=passed \
    claim_kind=local-structural mutation_id="mutation.coverage" \
    reason="" \
    evidence=""
else
  record_check id=mutation.coverage suite=mutation mandatory=true state=failed \
    reason="validators without a mutation case:${missing}" \
    claim_kind=local-structural mutation_id="mutation.coverage"
fi
# Excluded by design (documented): offline.install.* and offline.materialize.*
# are setup plumbing with no artifact judgment — their failures cascade into
# every generation validator above; offline.base guards a missing anchor;
# run.pristine is cross-suite; thin variant wrappers (stdio-only,
# unsupported-construct, negative-*) share the proven generation/refusal paths.

# ---- T058: the committed fixture and repository are unchanged
FIX_AFTER="$("${E2E_ROOT}/tools/digest.py" "${E2E_ROOT}/fixtures")"
REPO_AFTER="$("${E2E_ROOT}/tools/digest.py" "${REPO_ROOT}/loom.sh" \
  "${REPO_ROOT}/lib" "${REPO_ROOT}/install.sh" \
  "${REPO_ROOT}/skills" "${REPO_ROOT}/harness-specs" | sha256sum | awk '{print $1}')"
if [[ "${FIX_BEFORE}" == "${FIX_AFTER}" && "${REPO_BEFORE}" == "${REPO_AFTER}" ]]; then
  record_check id=mutation.isolation suite=mutation mandatory=true state=passed \
    claim_kind=local-structural mutation_id="mutation.isolation"
else
  record_check id=mutation.isolation suite=mutation mandatory=true state=failed \
    reason="fixture or repository tree changed during mutation run" \
    claim_kind=local-structural mutation_id="mutation.isolation"
fi
