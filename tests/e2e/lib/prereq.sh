#!/usr/bin/env bash
# lib/prereq.sh — prerequisite checks (T007).
#
# Reports each prerequisite individually. Exits 5 only when base tooling that
# every suite needs (bash 5+, git, jq, python3 3.11+) is missing. Anything a
# single suite needs — the bootstrapped venv, harness CLIs, live credentials —
# is reported as a status line and exported as E2E_HAVE_* so the owning suite
# can record an honest `blocked` check (FR-047) instead of failing the runner.
#
# Env in: E2E_SUITES (csv), E2E_HARNESSES (csv), E2E_ROOT (tests/e2e dir).
# Env out (exported): E2E_HAVE_VENV, E2E_HAVE_CLAUDE, E2E_HAVE_CODEX,
#   E2E_HAVE_OPENCODE, E2E_HAVE_CREDS.
# shellcheck disable=SC2034
E2E_HAVE_VENV=0; E2E_HAVE_CLAUDE=0; E2E_HAVE_CODEX=0; E2E_HAVE_OPENCODE=0
E2E_HAVE_CREDS=0
_prereq_fatal=0

_prereq_line() {  # <name> <ok:0|1> <detail>
  if [[ "$2" -eq 0 ]]; then echo "prereq: ok      $1 ($3)";
  else echo "prereq: MISSING $1 ($3)"; fi
}

# --- base tooling: fatal for any suite
if [[ "${BASH_VERSINFO[0]}" -ge 5 ]]; then _prereq_line "bash>=$BASH_VERSION" 0 "${BASH_VERSION}";
else _prereq_line "bash>=5" 1 "found ${BASH_VERSION}"; _prereq_fatal=1; fi

if command -v git >/dev/null 2>&1; then _prereq_line "git" 0 "$(git --version)";
else _prereq_line "git" 1 "not on PATH"; _prereq_fatal=1; fi

if command -v jq >/dev/null 2>&1; then _prereq_line "jq" 0 "$(jq --version)";
else _prereq_line "jq" 1 "not on PATH"; _prereq_fatal=1; fi

if command -v python3 >/dev/null 2>&1; then
  _pyver="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || echo "?")"
  _pymaj="$(python3 -c 'import sys; print(sys.version_info[0])' 2>/dev/null || echo 0)"
  _pymin="$(python3 -c 'import sys; print(sys.version_info[1])' 2>/dev/null || echo 0)"
  if [[ "${_pymaj}" -gt 3 || ( "${_pymaj}" -eq 3 && "${_pymin}" -ge 11 ) ]]; then
    _prereq_line "python3>=3.11" 0 "${_pyver}"
  else
    _prereq_line "python3>=3.11" 1 "found ${_pyver}"; _prereq_fatal=1
  fi
else
  _prereq_line "python3>=3.11" 1 "not on PATH"; _prereq_fatal=1
fi

# --- suite-scoped needs: reported, never fatal here
if [[ -x "${E2E_ROOT}/.venv/bin/python" ]] \
  && "${E2E_ROOT}/.venv/bin/python" -c 'import jsonschema' 2>/dev/null; then
  E2E_HAVE_VENV=1; _prereq_line "venv+jsonschema" 0 "${E2E_ROOT}/.venv"
else
  _prereq_line "venv+jsonschema" 1 "run tests/e2e/run.sh --bootstrap; schema checks will report blocked"
fi

if command -v claude >/dev/null 2>&1; then
  E2E_HAVE_CLAUDE=1; _prereq_line "claude" 0 "$(claude --version 2>/dev/null | head -1)"
else _prereq_line "claude" 1 "live/intent layers will report blocked"; fi

if command -v codex >/dev/null 2>&1; then
  E2E_HAVE_CODEX=1; _prereq_line "codex" 0 "$(codex --version 2>/dev/null | head -1)"
else _prereq_line "codex" 1 "codex conformance will report blocked"; fi

if command -v opencode >/dev/null 2>&1; then
  E2E_HAVE_OPENCODE=1; _prereq_line "opencode" 0 "$(opencode --version 2>/dev/null | head -1)"
else _prereq_line "opencode" 1 "opencode conformance will report blocked"; fi

if [[ -n "${ANTHROPIC_API_KEY:-}" || -f "${HOME}/.claude/.credentials.json" ]]; then
  E2E_HAVE_CREDS=1; _prereq_line "live-credentials" 0 "present"
else
  _prereq_line "live-credentials" 1 "live/intent layers will report blocked"
fi

export E2E_HAVE_VENV E2E_HAVE_CLAUDE E2E_HAVE_CODEX E2E_HAVE_OPENCODE E2E_HAVE_CREDS
if [[ "${_prereq_fatal}" -ne 0 ]]; then
  echo "prereq: base tooling missing — cannot run any suite (exit 5)" >&2
  exit 5
fi
