#!/usr/bin/env bash
# lib/assert.sh — check registration for the Loom e2e runner.
#
# Suites source this file with E2E_RUN_DIR exported. Each check is exactly one
# JSON line appended to $E2E_RUN_DIR/checks.jsonl, conforming to the `check`
# definition in specs/001-e2e-test-system/contracts/results.schema.json.
# The verdict is computed from these records by lib/result.sh — a pass can
# never be asserted by hand.
#
# Usage:
#   record_check id=<id> suite=<suite> mandatory=<true|false> state=<state>
#     [reason=<text>] [claim_kind=<kind>] [harness=<h>] [version=<v>]
#     [pinned=<true|false>] [interface=<cmd>] [gap_id=<g>] [mutation_id=<m>]
#     [capabilities=<csv>] [evidence=<csv>] [duration_ms=<n>]
#
# States: passed | failed | approved-gap | skipped | blocked
# Claim kinds: official-schema | harness-loader-probe | behaviour-probe |
#   local-structural | none
# shellcheck disable=SC2155
: "${E2E_RUN_DIR:?E2E_RUN_DIR must be exported before sourcing assert.sh}"

record_check() {
  local id="" suite="" mandatory="true" state="" reason="" claim_kind="none"
  local harness="" version="" pinned="true" interface="" gap_id=""
  local mutation_id="" capabilities="" evidence="" duration_ms="0"
  local attempts_json="" forbidden="false"
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "${k}" in
      id|suite|mandatory|state|reason|claim_kind|harness|version|pinned|\
      interface|gap_id|mutation_id|capabilities|evidence|duration_ms|\
      attempts_json|forbidden)
        printf -v "${k}" '%s' "${v}" ;;
      *) echo "record_check: unknown key '${k}'" >&2; return 2 ;;
    esac
  done
  [[ -n "${id}" && -n "${suite}" && -n "${state}" ]] \
    || { echo "record_check: id, suite and state are required" >&2; return 2; }
  case "${state}" in
    passed|failed|approved-gap|skipped|blocked) ;;
    *) echo "record_check: bad state '${state}'" >&2; return 2 ;;
  esac
  if [[ "${state}" != "passed" && -z "${reason}" ]]; then
    echo "record_check: non-passed check '${id}' requires a reason" >&2; return 2
  fi
  if [[ "${state}" == "approved-gap" && -z "${gap_id}" ]]; then
    echo "record_check: approved-gap check '${id}' requires gap_id" >&2; return 2
  fi
  if [[ "${suite}" == "mutation" && -z "${mutation_id}" ]]; then
    echo "record_check: mutation check '${id}' requires mutation_id" >&2; return 2
  fi
  local now_ms
  now_ms="$(date +%s%3N 2>/dev/null || echo 0)"
  jq -c -n \
    --arg id "${id}" --arg suite "${suite}" \
    --argjson mandatory "$( [[ "${mandatory}" == "true" ]] && echo true || echo false )" \
    --arg state "${state}" --arg reason "${reason}" \
    --arg claim_kind "${claim_kind}" \
    --arg harness "${harness}" --arg version "${version}" \
    --argjson pinned "$( [[ "${pinned}" == "false" ]] && echo false || echo true )" \
    --arg interface "${interface}" --arg gap_id "${gap_id}" \
    --arg mutation_id "${mutation_id}" --arg capabilities "${capabilities}" \
    --arg evidence "${evidence}" --argjson duration_ms "${duration_ms}" \
    --arg attempts_json "${attempts_json}" \
    --argjson forbidden "$( [[ "${forbidden}" == "true" ]] && echo true || echo false )" \
    --argjson now "${now_ms}" '
    {
      id: $id, suite: $suite, mandatory: $mandatory, state: $state,
      claim_kind: $claim_kind, pinned: $pinned,
      attempts: (if $attempts_json != "" then ($attempts_json | fromjson)
        else [{n: 1, state: $state}
          + (if $reason != "" then {reason: $reason} else {} end)] end),
      evidence: (if $evidence == "" then [] else ($evidence | split(",")) end),
      duration_ms: $duration_ms
    }
    + (if $forbidden then {forbidden_side_effect_observed: true} else {} end)
    + (if $reason != "" then {reason: $reason} else {} end)
    + (if $harness != "" then {harness: $harness} else {} end)
    + (if $version != "" then {harness_version_observed: $version} else {} end)
    + (if $interface != "" then {interface: $interface} else {} end)
    + (if $gap_id != "" then {gap_id: $gap_id} else {} end)
    + (if $mutation_id != "" then {mutation_id: $mutation_id} else {} end)
    + (if $capabilities != ""
       then {capability_ids: ($capabilities | split(","))} else {} end)
    ' >> "${E2E_RUN_DIR}/checks.jsonl"
}

# record_capability — one CapabilityOutcome line per (capability, harness).
# States: preserved | verified-compensated | approved-gap | failed | unverified
record_capability() {
  local capability_id="" harness="" state="" gap_id="" evidence="" checks=""
  local native_exists="" native_evidence="" verified_by=""
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "${k}" in
      capability_id|harness|state|gap_id|evidence|checks|native_exists|\
      native_evidence|verified_by) printf -v "${k}" '%s' "${v}" ;;
      *) echo "record_capability: unknown key '${k}'" >&2; return 2 ;;
    esac
  done
  [[ -n "${capability_id}" && -n "${harness}" && -n "${state}" ]] \
    || { echo "record_capability: capability_id, harness, state required" >&2; return 2; }
  jq -c -n \
    --arg capability_id "${capability_id}" --arg harness "${harness}" \
    --arg state "${state}" --arg gap_id "${gap_id}" \
    --arg evidence "${evidence}" --arg checks "${checks}" \
    --arg native_exists "${native_exists}" \
    --arg native_evidence "${native_evidence}" \
    --arg verified_by "${verified_by}" '
    {capability_id: $capability_id, harness: $harness, state: $state}
    + (if $gap_id != "" then {gap_id: $gap_id} else {} end)
    + (if $native_exists != ""
       then {native_equivalent: ({exists: ($native_exists == "true")}
         + (if $native_evidence != "" then {evidence: $native_evidence}
            else {} end))} else {} end)
    + (if $verified_by != ""
       then {compensating_control_verified_by: $verified_by} else {} end)
    + {evidence: (if $evidence == "" then [] else ($evidence | split(",")) end)}
    + {checks: (if $checks == "" then [] else ($checks | split(",")) end)}
    ' >> "${E2E_RUN_DIR}/capabilities.jsonl"
}
