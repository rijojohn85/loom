#!/usr/bin/env bash
# lib/evidence.sh — per-check evidence dirs, digest manifests, redaction (T015).
#
#   evidence_dir <check-id>     -> path, created under $E2E_RUN_DIR/evidence/
#   retain_file <check-id> <src> [name]
#     redaction pass first (tools/redact.py); refuses credential-matching
#     files instead of writing them (FR-026). Prints the run-relative path.
#   digest_manifest <dir>       -> sha256 manifest of <dir> on stdout.
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}"

evidence_dir() {
  local d="${E2E_RUN_DIR}/evidence/$1"
  mkdir -p "${d}"
  echo "${d}"
}

retain_file() {  # <check-id> <src> [name]
  local id="$1" src="$2" name="${3:-$(basename "$2")}"
  [[ -f "${src}" ]] || { echo "retain_file: no source ${src}" >&2; return 2; }
  if ! "${E2E_ROOT}/tools/redact.py" "${src}" >/dev/null 2>&1; then
    echo "retain_file: redaction refused ${src}" >&2
    "${E2E_ROOT}/tools/redact.py" "${src}" 2>&1 | head -3 >&2 || true
    # A credential pattern in retained evidence fails the run, it is not
    # silently dropped (T095, T112, SC-012).
    if ! command -v record_check >/dev/null 2>&1; then
      # shellcheck disable=SC1091
      source "${E2E_ROOT}/lib/assert.sh"
    fi
    # Suite must stay inside the results-schema enum (T113): a check-id with
    # a non-suite prefix falls back to the first selected suite, not "run".
    local suite="${id%%.*}"
    case "${suite}" in offline|mutation|live|conformance|intent) ;;
      *) suite="${E2E_SUITES%%,*}"
         case "${suite}" in offline|mutation|live|conformance|intent) ;;
           *) suite="offline" ;;
         esac ;;
    esac
    if [[ "${suite}" == "mutation" ]]; then
      record_check id="evidence.redaction" "suite=${suite}" mandatory=true \
        state=failed claim_kind=none mutation_id="evidence.redaction" \
        reason="retention refused for ${id}/${name}: file matches a credential pattern (nothing written)"
    else
      record_check id="evidence.redaction" "suite=${suite}" mandatory=true \
        state=failed claim_kind=none \
        reason="retention refused for ${id}/${name}: file matches a credential pattern (nothing written)"
    fi
    return 1
  fi
  local d
  d="$(evidence_dir "${id}")"
  cp "${src}" "${d}/${name}"
  echo "evidence/${id}/${name}"
}

digest_manifest() {  # <dir>
  local dir="$1" f
  while IFS= read -r -d '' f; do
    sha256sum "${f}" | sed "s| ${dir}/|  |"
  done < <(find "${dir}" -type f -print0 | LC_ALL=C sort -z)
}
