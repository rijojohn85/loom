#!/usr/bin/env bash
# suites/conformance/canary.sh — trust canary + customisation negative
# control (T075, T076, research D11). Sourced.
#
# canary_check <harness> <workspace>
#   Unseeded probe must show the trust gate (codex: empty list; claude:
#   pending approval); the seeded probe must show the servers; the two must
#   differ. opencode has no gate — asserted loading in both states and the
#   absence of a gate recorded. With E2E_NO_TRUST_SEED=1 only the unseeded
#   probe runs: a trust-gated harness that still sees project config fails.
#
# negative_control <harness> <workspace>
#   The same probe re-run with customisation disabled (codex: project config
#   removed from a copy; opencode: opencode.json removed from a copy;
#   claude: -p --safe-mode when credentialed). A canary visible in both runs
#   proves the probe reads something other than project config → fail.
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh" 2>/dev/null || true

_conf_out() {  # <harness> <check> <state> <reason> <claim> [pinned] [interface]
  local h="$1" chk="$2" state="$3" reason="$4" claim="$5" pinned="${6:-true}"
  local interface="${7:-trust-canary}" ver
  # Advisory version mismatch downgrades every conformance claim (T080).
  if [[ "${H_ADVISORY[${h}]:-0}" == "1" ]]; then
    pinned="false"
    claim="local-structural"
    [[ "${reason}" != *"advisory"* ]] && reason="${reason} (advisory: observed version differs from pin)"
  fi
  ver="$(jq -r --arg h "${h}" '.harnesses[$h].version_observed // empty' \
    "${E2E_RUN_DIR}/pins.json")"
  local -a pargs=(id="${chk}" suite=conformance mandatory=true "state=${state}"
    "claim_kind=${claim}" "harness=${h}" "pinned=${pinned}"
    "interface=${interface}")
  [[ -n "${reason}" ]] && pargs+=("reason=${reason}")
  [[ -n "${ver}" ]] && pargs+=("version=${ver}")
  # shellcheck disable=SC2086
  record_check "${pargs[@]}"
}

_neg_out() {  # same as _conf_out but for the customisation negative control
  _conf_out "$1" "$2" "$3" "$4" "$5" "${6:-true}" "customisation-negative"
}

canary_check() {  # <harness> <workspace>
  local h="$1" ws="$2" unseeded seeded
  # shellcheck disable=SC1091,SC1090
  source "${E2E_ROOT}/probes/${h}.sh"
  case "${h}" in
    codex)
      unseeded="$(cd "${ws}" && run_isolated codex mcp list --json 2>/dev/null || echo FAILED)"
      if [[ "${E2E_NO_TRUST_SEED:-0}" == "1" ]]; then
        if [[ "${unseeded}" == "[]" ]]; then
          _conf_out codex conformance.codex.untrusted-canary passed \
            "unseeded codex returned [] with exit 0 (gate signs present)" \
            harness-loader-probe
        else
          _conf_out codex conformance.codex.untrusted-canary failed \
            "unseeded codex saw project config — probe is not reading project state" \
            harness-loader-probe
        fi
        return 0
      fi
      seed_trust "${ws}" docs-a docs-b docs-local >/dev/null 2>&1 || true
      seeded="$(cd "${ws}" && run_isolated codex mcp list --json 2>/dev/null || echo FAILED)"
      if [[ "${unseeded}" == "[]" ]] && grep -q "docs-a" <<<"${seeded}"; then
        _conf_out codex conformance.codex.untrusted-canary passed \
          "unseeded [] vs seeded servers — probe reads project config" \
          harness-loader-probe
      elif [[ "${unseeded}" != "[]" ]]; then
        _conf_out codex conformance.codex.untrusted-canary failed \
          "unseeded codex saw project config — the gate this check relies on is gone" \
          harness-loader-probe
      else
        _conf_out codex conformance.codex.untrusted-canary failed \
          "seeded codex did not resolve fixture servers" \
          harness-loader-probe
      fi ;;
    claude)
      unseeded="$(cd "${ws}" && run_isolated claude mcp list 2>&1 || echo FAILED)"
      if [[ "${E2E_NO_TRUST_SEED:-0}" == "1" ]]; then
        if grep -q "Pending approval" <<<"${unseeded}"; then
          _conf_out claude conformance.claude.untrusted-canary passed \
            "unseeded claude reports pending approval (gate signs present)" \
            harness-loader-probe
        else
          _conf_out claude conformance.claude.untrusted-canary failed \
            "unseeded claude shows no approval gate — probe may read the wrong config" \
            harness-loader-probe
        fi
        return 0
      fi
      seed_trust "${ws}" docs-a docs-b docs-local >/dev/null 2>&1 || true
      seeded="$(cd "${ws}" && run_isolated claude mcp list 2>&1 || echo FAILED)"
      if grep -q "Pending approval" <<<"${unseeded}" \
        && ! grep -q "Pending approval" <<<"${seeded}"; then
        _conf_out claude conformance.claude.untrusted-canary passed \
          "pending-approval unseeded vs attempted seeded — seeding changed the state" \
          harness-loader-probe
      elif ! grep -q "Pending approval" <<<"${unseeded}"; then
        _conf_out claude conformance.claude.untrusted-canary failed \
          "unseeded claude shows no approval gate" \
          harness-loader-probe
      else
        _conf_out claude conformance.claude.untrusted-canary failed \
          "seeded claude still pending approval — seeding did not take" \
          harness-loader-probe
      fi ;;
    opencode)
      unseeded="$(cd "${ws}" && run_isolated opencode debug config 2>/dev/null | jq -r '.mcp | keys | join(",")' 2>/dev/null || echo FAILED)"
      if [[ "${unseeded}" == *"docs-a"* ]]; then
        _conf_out opencode conformance.opencode.untrusted-canary passed \
          "opencode loads project config with no trust gate (observed fact, both states)" \
          harness-loader-probe
      else
        _conf_out opencode conformance.opencode.untrusted-canary failed \
          "opencode did not load project config even unseeded" \
          harness-loader-probe
      fi ;;
  esac
}

negative_control() {  # <harness> <workspace>
  local h="$1" ws="$2" normal disabled copy
  case "${h}" in
    codex)
      normal="$(cd "${ws}" && run_isolated codex mcp list --json 2>/dev/null | jq -r '.[].name' 2>/dev/null | sort | tr '\n' ',')"
      copy="${E2E_RUN_DIR}/conformance/negcopy-codex"
      rm -rf "${copy}"
      cp -a "${ws}" "${copy}"
      rm -rf "${copy}/.codex"
      disabled="$(cd "${copy}" && run_isolated codex mcp list --json 2>/dev/null | jq -r '.[].name' 2>/dev/null | sort | tr '\n' ',')"
      rm -rf "${copy}"
      if [[ "${normal}" == *"docs-a"* && "${disabled}" != *"docs-a"* ]]; then
        _neg_out codex conformance.codex.customisation-negative passed \
          "servers visible normally, absent with project config removed" \
          harness-loader-probe
      elif [[ "${normal}" == *"docs-a"* ]]; then
        _neg_out codex conformance.codex.customisation-negative failed \
          "canary visible with project config removed — probe reads the wrong state" \
          harness-loader-probe
      else
        _neg_out codex conformance.codex.customisation-negative failed \
          "canary absent even in the normal run" \
          harness-loader-probe
      fi ;;
    opencode)
      normal="$(cd "${ws}" && run_isolated opencode debug config 2>/dev/null | jq -r '.mcp | keys | join(",")' 2>/dev/null || echo FAILED)"
      copy="${E2E_RUN_DIR}/conformance/negcopy-opencode"
      rm -rf "${copy}"
      cp -a "${ws}" "${copy}"
      rm -f "${copy}/opencode.json"
      disabled="$(cd "${copy}" && run_isolated opencode debug config 2>/dev/null | jq -r '.mcp | keys | join(",")' 2>/dev/null || echo FAILED)"
      rm -rf "${copy}"
      if [[ "${normal}" == *"docs-a"* && "${disabled}" != *"docs-a"* ]]; then
        _neg_out opencode conformance.opencode.customisation-negative passed \
          "servers visible normally, absent with project config removed" \
          harness-loader-probe
      elif [[ "${normal}" == *"docs-a"* ]]; then
        _neg_out opencode conformance.opencode.customisation-negative failed \
          "canary visible with project config removed — probe reads the wrong state" \
          harness-loader-probe
      else
        _neg_out opencode conformance.opencode.customisation-negative failed \
          "canary absent even in the normal run" \
          harness-loader-probe
      fi ;;
    claude)
      if [[ "${E2E_HAVE_CREDS:-0}" != "1" ]]; then
        _neg_out claude conformance.claude.customisation-negative blocked \
          "no live credentials for the --safe-mode negative control" \
          harness-loader-probe
        return 0
      fi
      # Auto-loading control: the normal run must quote project context it
      # never explicitly read (no Read of AGENTS.md/CLAUDE.md in the
      # transcript) — that proves auto-loading. --safe-mode disables
      # auto-loading, so a quote there without a Read fails the probe.
      _ctx_quote() {  # <stream-file> -> 0 iff deny+gap quoted
        grep -qi "deny" "$1" 2>/dev/null \
          && grep -Eqi "gap|reviewed" "$1" 2>/dev/null
      }
      _ctx_reads() {  # <stream-file> -> 0 iff project context observably accessed
        # Read tool uses…
        jq -s -e '[.. | objects | select(.name == "Read") | .input.file_path // empty]
          | map(select(test("AGENTS\\.md|CLAUDE\\.md"))) | length > 0' \
          "$1" >/dev/null 2>&1 && return 0
        # …or shell access (cat/grep/head/sed/… AGENTS.md|CLAUDE.md). The
        # stream encodes inner quotes escaped, so [^"]* cannot span them.
        grep -Eq '"command"[ ]*:[ ]*".*(cat|grep|head|sed|less|awk).*(AGENTS\.md|CLAUDE\.md)' \
          "$1" 2>/dev/null
      }
      normal_out="$(cd "${ws}" && run_isolated claude -p --output-format stream-json --verbose \
        --setting-sources user,project,local \
        "What project-specific rules govern how you make edits here? Cite the exact rule text." \
        < /dev/null 2>&1 || true)"
      disabled_out="$(cd "${ws}" && run_isolated claude -p --output-format stream-json --verbose \
        --setting-sources user,project,local --safe-mode \
        "What project-specific rules govern how you make edits here? Cite the exact rule text." \
        < /dev/null 2>&1 || true)"
      printf '%s' "${normal_out}" > "${E2E_RUN_DIR}/conformance/claude-ctx-normal.jsonl"
      printf '%s' "${disabled_out}" > "${E2E_RUN_DIR}/conformance/claude-ctx-disabled.jsonl"
      # Rejected credentials: blocked with the prerequisite named, never a
      # failed "baseline did not quote" (Pr. VIII) (T107).
      if _claude_auth_failed "${normal_out}"; then
        _neg_out claude conformance.claude.customisation-negative blocked \
          "no usable live credentials for the --safe-mode negative control (OAuth token expired or invalid)" \
          harness-loader-probe
        return 0
      fi
      # Quoted? Read explicitly? A safe-mode quote WITHOUT a read is
      # impossible through loading — that fails the probe. Explicit reads
      # are tolerated (safe-mode allows reads; only auto-load is gated).
      normal_q=0; normal_r=0; disabled_q_unread=0
      if _ctx_quote "${E2E_RUN_DIR}/conformance/claude-ctx-normal.jsonl"; then
        normal_q=1
      fi
      if _ctx_reads "${E2E_RUN_DIR}/conformance/claude-ctx-normal.jsonl"; then
        normal_r=1
      fi
      if _ctx_quote "${E2E_RUN_DIR}/conformance/claude-ctx-disabled.jsonl" \
        && ! _ctx_reads "${E2E_RUN_DIR}/conformance/claude-ctx-disabled.jsonl"; then
        disabled_q_unread=1
      fi
      if [[ "${normal_q}" -eq 1 && "${disabled_q_unread}" -eq 0 ]]; then
        if [[ "${normal_r}" -eq 0 ]]; then
          _neg_out claude conformance.claude.customisation-negative passed \
            "context quoted from auto-load normally (no explicit read); not quoted unloaded under --safe-mode" \
            harness-loader-probe
        else
          _neg_out claude conformance.claude.customisation-negative passed \
            "context quoted normally (via explicit read); not quoted unloaded under --safe-mode" \
            harness-loader-probe
        fi
      elif [[ "${normal_q}" -eq 0 ]]; then
        _neg_out claude conformance.claude.customisation-negative failed \
          "baseline did not quote project context in the normal run" \
          harness-loader-probe
      else
        _neg_out claude conformance.claude.customisation-negative failed \
          "canary quoted under --safe-mode without an explicit read — probe reads the wrong state" \
          harness-loader-probe
      fi ;;
  esac
}
