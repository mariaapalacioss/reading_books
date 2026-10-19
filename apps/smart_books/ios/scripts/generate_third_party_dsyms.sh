#!/bin/bash
# Vendored frameworks (PDFium, objective_c) ship without dSYMs; App Store upload expects them.
set -euo pipefail

if [[ "${CONFIGURATION}" != "Release" && "${CONFIGURATION}" != "Profile" ]]; then
  exit 0
fi

FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
DSYM_OUTPUT_DIR="${DWARF_DSYM_FOLDER_PATH}"

if [[ ! -d "${FRAMEWORKS_DIR}" ]]; then
  exit 0
fi

generate_dsym() {
  local name="$1"
  local fw_path="${FRAMEWORKS_DIR}/${name}.framework"
  local binary="${fw_path}/${name}"

  if [[ ! -f "${binary}" ]]; then
    return 0
  fi

  local out="${DSYM_OUTPUT_DIR}/${name}.framework.dSYM"
  if [[ -d "${out}" ]]; then
    return 0
  fi

  echo "note: Generating dSYM for ${name}.framework (App Store symbols)"
  mkdir -p "${DSYM_OUTPUT_DIR}"
  xcrun dsymutil "${binary}" -o "${out}" || echo "warning: dsymutil failed for ${name}.framework"
}

generate_dsym "PDFium"
generate_dsym "objective_c"
