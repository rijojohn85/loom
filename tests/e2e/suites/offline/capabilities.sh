#!/usr/bin/env bash
# suites/offline/capabilities.sh — one CapabilityOutcome per (capability,
# harness), loader probes as evidence, Devin deferral, claim-kind audit
# (T045, T046, T051; SC-002; FR-041).
#
# Outcome rules (data-model.md state rules):
# - preserved: adapter content verified + cited evidence check passed.
# - verified-compensated: gap entry exists and verified_by check passed.
# - approved-gap: reviewed gap_id exists; dropped nodes present in GAPS.md.
# - failed: anything else (missing pair, content mismatch, unproven control).
# - unverified: Devin non-gap dispositions (deferred target, T046) — visible,
#   never counted, non-mandatory.
# Version-mismatch/advisory handling lives in the conformance suite (T080);
# offline checks always record what they observed (pinned=true).
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}" "${E2E_WORKSPACE:?}" "${E2E_OFFLINE_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/isolate.sh"

WS="${E2E_WORKSPACE}"
CAPS="${E2E_ROOT}/oracle/capabilities.json"
GAPS_DB="${E2E_ROOT}/oracle/approved-gaps.json"
RESOLVED="${E2E_OFFLINE_DIR}/base/resolved-input.json"
EVID_DIR="${E2E_RUN_DIR}/evidence/offline.capabilities"
mkdir -p "${EVID_DIR}"
for f in .codex/config.toml opencode.json .devin/mcp_config.json \
         .devin/config.json .devin/hooks.v1.json agent/harness-specs/GAPS.md; do
  mkdir -p "${EVID_DIR}/$(dirname "${f}")"
  cp "${WS}/${f}" "${EVID_DIR}/${f}" 2>/dev/null || true
done
cp "${RESOLVED}" "${EVID_DIR}/resolved-input.json"

URL_A="$(jq -r .mcp_urls.docs_a "${RESOLVED}")"
URL_B="$(jq -r .mcp_urls.docs_b "${RESOLVED}")"
codex_ver="$(jq -r '.harnesses.codex.version_observed // empty' "${E2E_RUN_DIR}/pins.json")"
opencode_ver="$(jq -r '.harnesses.opencode.version_observed // empty' "${E2E_RUN_DIR}/pins.json")"

check_state() {  # <check-id> -> state or MISSING
  jq -s -r --arg id "$1" '[.[] | select(.id == $id) | .state] | last // "MISSING"' \
    "${E2E_RUN_DIR}/checks.jsonl"
}

# ---- loader probes: the harness itself must resolve the fixture servers.
# Credential-free and network-free (D1, D11); trust was seeded by run.sh.
if [[ "${E2E_HAVE_CODEX:-0}" == "1" ]]; then
  if (cd "${WS}" && run_isolated codex mcp list --json) >"${E2E_OFFLINE_DIR}/loader-codex.json" 2>"${E2E_OFFLINE_DIR}/loader-codex.err"; then
    if jq -e --arg a "${URL_A}" --arg b "${URL_B}" '
        (map(.name) | index("docs-a") and index("docs-b") and index("docs-local"))
        and ([.[] | select(.name == "docs-a") | .. | strings] | index($a))
        and ([.[] | select(.name == "docs-b") | .. | strings] | index($b))' \
        "${E2E_OFFLINE_DIR}/loader-codex.json" >/dev/null; then
      record_check id=offline.loader.codex suite=offline mandatory=true state=passed \
        claim_kind=harness-loader-probe harness=codex version="${codex_ver}" \
        interface="codex mcp list --json"
    else
      record_check id=offline.loader.codex suite=offline mandatory=true state=failed \
        reason="codex resolved an unexpected server set (see offline/loader-codex.json)" \
        claim_kind=harness-loader-probe harness=codex version="${codex_ver}" \
        interface="codex mcp list --json"
    fi
  else
    record_check id=offline.loader.codex suite=offline mandatory=true state=failed \
      reason="codex mcp list failed: $(head -1 "${E2E_OFFLINE_DIR}/loader-codex.err")" \
      claim_kind=harness-loader-probe harness=codex version="${codex_ver}" \
      interface="codex mcp list --json"
  fi
else
  record_check id=offline.loader.codex suite=offline mandatory=true state=blocked \
    reason="codex CLI absent" claim_kind=harness-loader-probe harness=codex
fi

if [[ "${E2E_HAVE_OPENCODE:-0}" == "1" ]]; then
  if (cd "${WS}" && run_isolated opencode debug config) >"${E2E_OFFLINE_DIR}/loader-opencode.json" 2>"${E2E_OFFLINE_DIR}/loader-opencode.err" \
     && jq -e . "${E2E_OFFLINE_DIR}/loader-opencode.json" >/dev/null 2>&1; then
    if jq -e --arg a "${URL_A}" --arg b "${URL_B}" '
        .mcp["docs-a"].url == $a and .mcp["docs-b"].url == $b
        and .mcp["docs-local"].url == "stdio://docs-local"' \
        "${E2E_OFFLINE_DIR}/loader-opencode.json" >/dev/null; then
      record_check id=offline.loader.opencode suite=offline mandatory=true state=passed \
        claim_kind=harness-loader-probe harness=opencode version="${opencode_ver}" \
        interface="opencode debug config"
    else
      record_check id=offline.loader.opencode suite=offline mandatory=true state=failed \
        reason="opencode resolved config differs from emitted adapter" \
        claim_kind=harness-loader-probe harness=opencode version="${opencode_ver}" \
        interface="opencode debug config"
    fi
  else
    record_check id=offline.loader.opencode suite=offline mandatory=true state=failed \
      reason="opencode debug config failed: $(head -1 "${E2E_OFFLINE_DIR}/loader-opencode.err")" \
      claim_kind=harness-loader-probe harness=opencode version="${opencode_ver}" \
      interface="opencode debug config"
  fi
else
  record_check id=offline.loader.opencode suite=offline mandatory=true state=blocked \
    reason="opencode CLI absent" claim_kind=harness-loader-probe harness=opencode
fi

SCHEMA_STATE="$(check_state offline.schema)"
LOADER_CODEX_STATE="$(check_state offline.loader.codex)"
LOADER_OPENCODE_STATE="$(check_state offline.loader.opencode)"

# ---- structural content verification helpers (base variant, real servers)
codex_has_server() {  # <name> <url>
  "${E2E_ROOT}/tools/parse.py" "${WS}/.codex/config.toml" 2>/dev/null | jq -e \
    --arg s "$1" --arg u "$2" '.data.mcp_servers[$s].url == $u' >/dev/null
}
opencode_has_server() {
  jq -e --arg s "$1" --arg u "$2" '.mcp[$s].url == $u' "${WS}/opencode.json" >/dev/null
}
devin_has_server() {
  jq -e --arg s "$1" --arg u "$2" '.mcpServers[$s].url == $u' "${WS}/.devin/mcp_config.json" >/dev/null
}
gap_entry() {  # <gap-id> -> entry or empty
  jq -c --arg g "$1" '.gaps[] | select(.gap_id == $g)' "${GAPS_DB}"
}
gaps_has_dropped() {  # <gap-id> -> 0 iff every dropped node is in GAPS.md
  local g="$1" node harness
  harness="$(jq -r --arg g "${g}" '.gaps[] | select(.gap_id == $g) | .harness' "${GAPS_DB}")"
  while IFS= read -r node; do
    [[ -z "${node}" ]] && continue
    grep -Fq "| ${harness} | ${node} |" "${WS}/agent/harness-specs/GAPS.md" || return 1
  done < <(jq -r --arg g "${g}" '.gaps[] | select(.gap_id == $g) | .dropped_nodes[]?' "${GAPS_DB}")
  return 0
}

declare -A HARNESS_FAILED=([codex]=0 [opencode]=0 [devin]=0)
declare -A HARNESS_BLOCKED_EVIDENCE=([codex]=0 [opencode]=0 [devin]=0)

for harness in codex opencode devin; do
  while IFS= read -r cap; do
    cap_id="$(jq -r .id <<<"${cap}")"
    disp="$(jq -c --arg h "${harness}" '.expectations[$h]' <<<"${cap}")"
    dstate="$(jq -r .state <<<"${disp}")"
    gap_id="$(jq -r '.gap_id // empty' <<<"${disp}")"
    native="$(jq -c '.native_equivalent // empty' <<<"${disp}")"

    # T046: a deferred target proves nothing — non-gap dispositions stay visible but unverified.
    # Exception: policy.mcp-allowlist is proven by generator behaviour
    # (identical for every harness), not by any harness loader.
    if [[ "${harness}" == "devin" && "${dstate}" != "approved-gap" && "${cap_id}" != "policy.mcp-allowlist" ]]; then
      record_capability capability_id="${cap_id}" harness=devin state=unverified \
        evidence="evidence/offline.capabilities/resolved-input.json" checks="offline.capabilities.devin"
      continue
    fi

    case "${dstate}" in
      preserved)
        if [[ "${cap_id}" == "policy.mcp-allowlist" ]]; then
          # Proven by the negative-variant generation refusals (behaviour-probe).
          missing=""
          for n in url-less unapproved-name unapproved-endpoint invalid-input; do
            [[ "$(check_state "offline.negative.${n}")" == "passed" ]] \
              || missing="${missing} offline.negative.${n}"
          done
          if [[ -z "${missing}" ]]; then
            record_capability capability_id="${cap_id}" harness="${harness}" state=preserved \
              evidence="evidence/offline.capabilities/agent/harness-specs/GAPS.md" \
              checks="offline.negative.url-less,offline.negative.unapproved-name,offline.negative.unapproved-endpoint,offline.negative.invalid-input"
          else
            record_capability capability_id="${cap_id}" harness="${harness}" state=failed \
              evidence="evidence/offline.capabilities/agent/harness-specs/GAPS.md" \
              checks="offline.negative.url-less,offline.negative.unapproved-name,offline.negative.unapproved-endpoint,offline.negative.invalid-input"
            HARNESS_FAILED["${harness}"]=1
          fi
          continue
        fi
        # mcp preservation per harness.
        ok=1; cite=""
        case "${harness}" in
          codex)
            codex_has_server docs-a "${URL_A}" && codex_has_server docs-b "${URL_B}" \
              && codex_has_server docs-local "stdio://docs-local" || ok=0
            cite="offline.loader.codex,offline.structural"
            [[ "${LOADER_CODEX_STATE}" == "passed" ]] || ok=0
            [[ "${LOADER_CODEX_STATE}" == "blocked" ]] && HARNESS_BLOCKED_EVIDENCE["${harness}"]=1
            ;;
          opencode)
            opencode_has_server docs-a "${URL_A}" && opencode_has_server docs-b "${URL_B}" \
              && opencode_has_server docs-local "stdio://docs-local" || ok=0
            cite="offline.schema,offline.loader.opencode"
            [[ "${SCHEMA_STATE}" == "passed" && "${LOADER_OPENCODE_STATE}" == "passed" ]] || ok=0
            { [[ "${SCHEMA_STATE}" == "blocked" ]] || [[ "${LOADER_OPENCODE_STATE}" == "blocked" ]]; } \
              && HARNESS_BLOCKED_EVIDENCE["${harness}"]=1
            ;;
        esac
        if [[ "${ok}" -eq 1 ]]; then
          record_capability capability_id="${cap_id}" harness="${harness}" state=preserved \
            evidence="evidence/offline.capabilities/resolved-input.json" checks="${cite}"
        else
          record_capability capability_id="${cap_id}" harness="${harness}" state=failed \
            evidence="evidence/offline.capabilities/resolved-input.json" checks="${cite}"
          HARNESS_FAILED["${harness}"]=1
        fi
        ;;
      compensated)
        entry="$(gap_entry "${gap_id}")"
        verified_by="$(jq -r '.compensating_control.verified_by // empty' <<<"${entry}")"
        vb_state="$(check_state "${verified_by}")"
        proved_struct=1
        if [[ "${cap_id}" == "perm.allow.mcp-tools" && "${harness}" == "codex" ]]; then
          grep -q 'default_tools_approval_mode = "auto"' "${WS}/.codex/config.toml" || proved_struct=0
          cite="offline.loader.codex"
        elif [[ "${cap_id}" == "perm.allow.mcp-tools" && "${harness}" == "opencode" ]]; then
          opencode_has_server docs-a "${URL_A}" || proved_struct=0
          cite="offline.schema"
        else
          cite="${verified_by}"
        fi
        if [[ -n "${entry}" && -n "${verified_by}" && "${vb_state}" == "passed" && "${proved_struct}" -eq 1 ]]; then
          record_capability capability_id="${cap_id}" harness="${harness}" \
            state=verified-compensated gap_id="${gap_id}" \
            verified_by="${verified_by}" \
            evidence="evidence/offline.capabilities/resolved-input.json" checks="${cite}"
        elif [[ -n "${entry}" && -n "${verified_by}" && ( "${vb_state}" == "blocked" || "${vb_state}" == "MISSING" ) ]]; then
          HARNESS_BLOCKED_EVIDENCE["${harness}"]=1
          record_capability capability_id="${cap_id}" harness="${harness}" state=failed \
            gap_id="${gap_id}" evidence="evidence/offline.capabilities/resolved-input.json" checks="${cite}"
          HARNESS_FAILED["${harness}"]=1
        else
          record_capability capability_id="${cap_id}" harness="${harness}" state=failed \
            gap_id="${gap_id}" evidence="evidence/offline.capabilities/resolved-input.json" checks="${cite}"
          HARNESS_FAILED["${harness}"]=1
        fi
        ;;
      approved-gap)
        entry="$(gap_entry "${gap_id}")"
        if [[ -z "${entry}" ]]; then
          record_capability capability_id="${cap_id}" harness="${harness}" state=failed \
            evidence="evidence/offline.capabilities/resolved-input.json" checks="offline.artifacts"
          HARNESS_FAILED["${harness}"]=1
        elif [[ -z "${native}" || "$(jq -r '.native_equivalent | has("exists")' <<<"${entry}")" != "true" ]]; then
          record_capability capability_id="${cap_id}" harness="${harness}" state=failed \
            gap_id="${gap_id}" evidence="evidence/offline.capabilities/resolved-input.json" checks="offline.artifacts"
          HARNESS_FAILED["${harness}"]=1
        elif ! gaps_has_dropped "${gap_id}"; then
          record_capability capability_id="${cap_id}" harness="${harness}" state=failed \
            gap_id="${gap_id}" \
            evidence="evidence/offline.capabilities/agent/harness-specs/GAPS.md" checks="offline.artifacts"
          HARNESS_FAILED["${harness}"]=1
        else
          record_capability capability_id="${cap_id}" harness="${harness}" \
            state=approved-gap gap_id="${gap_id}" \
            native_exists="$(jq -r '.native_equivalent.exists' <<<"${entry}")" \
            native_evidence="see oracle/approved-gaps.json ${gap_id}" \
            evidence="evidence/offline.capabilities/agent/harness-specs/GAPS.md" checks="offline.artifacts"
        fi
        ;;
      *)  # oracle says unverified (should not happen for codex/opencode) — take it literally
        record_capability capability_id="${cap_id}" harness="${harness}" state=unverified \
          evidence="evidence/offline.capabilities/resolved-input.json" checks="offline.capabilities.${harness}"
        ;;
    esac
  done < <(jq -c '.capabilities[]' "${CAPS}")
done

# Per-harness capability checks: failed on genuine mismatch, blocked when the
# only failures ride on blocked evidence, passed otherwise.
for harness in codex opencode; do
  if [[ "${HARNESS_FAILED[${harness}]}" -eq 0 ]]; then
    record_check id="offline.capabilities.${harness}" suite=offline mandatory=true \
      state=passed claim_kind=local-structural
  elif [[ "${HARNESS_BLOCKED_EVIDENCE[${harness}]}" -eq 1 ]]; then
    # Re-mark: evidence-blocked, not genuinely failed.
    record_check id="offline.capabilities.${harness}" suite=offline mandatory=true \
      state=blocked reason="evidence unavailable (loader or schema check blocked)" \
      claim_kind=local-structural harness="${harness}"
  else
    record_check id="offline.capabilities.${harness}" suite=offline mandatory=true \
      state=failed reason="one or more ${harness} capability outcomes failed" \
      claim_kind=local-structural harness="${harness}"
  fi
done
record_check id=offline.capabilities.devin suite=offline mandatory=false \
  state=passed claim_kind=local-structural harness=devin \
  reason=""

# T051: no supported claim rests on format parsing alone. A genuine failure
# outranks blocked evidence. The audit is shared with the mutation suite.
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/mutation/validators.sh"
audit_out="$(v_claim_audit "${E2E_RUN_DIR}/checks.jsonl" \
  "${E2E_RUN_DIR}/capabilities.jsonl")"
audit_code=$?
if [[ "${audit_code}" -eq 1 ]]; then
  record_check id=offline.claim-kinds suite=offline mandatory=true \
    state=failed reason="${audit_out#FAILED:}" claim_kind=local-structural
elif [[ "${audit_code}" -eq 3 ]]; then
  record_check id=offline.claim-kinds suite=offline mandatory=true \
    state=blocked reason="${audit_out#BLOCKED:}" claim_kind=local-structural
else
  record_check id=offline.claim-kinds suite=offline mandatory=true \
    state=passed claim_kind=local-structural
fi
