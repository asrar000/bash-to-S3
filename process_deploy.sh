#!/bin/bash

# =============================================================================
# Processor Packaging Script
# Creates modules.zip from the configured ITEMS_TO_ZIP list and extracts the
# archive into S3-Upload while preserving file and directory names as-is.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Directory Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-${SCRIPT_DIR}}"
DEFAULT_PROCESSOR_DIR="${ROOT_DIR}/processor"

if [[ -n "${PROCESSOR_DIR:-}" ]]; then
    SOURCE_DIR="${PROCESSOR_DIR}"
elif [[ -d "${DEFAULT_PROCESSOR_DIR}" ]]; then
    SOURCE_DIR="${DEFAULT_PROCESSOR_DIR}"
else
    SOURCE_DIR="${ROOT_DIR}"
fi

OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/S3-Upload}"
ZIP_NAME="${ZIP_NAME:-modules.zip}"
ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"

# -----------------------------------------------------------------------------
# Logging Setup
# -----------------------------------------------------------------------------
CURRENT_DATE="$(date +%Y-%m-%d)"
CURRENT_DATETIME="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_BASE_DIR="${LOG_BASE_DIR:-${ROOT_DIR}/logs/deployer}"
LOG_DIR="${LOG_BASE_DIR}/${CURRENT_DATE}"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/rcron_processor_packager_${CURRENT_DATETIME}.log"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "${timestamp} - processor_packager - ${level} - ${message}" | tee -a "${LOG_FILE}"
}

log_info()     { log "INFO" "$@"; }
log_warning()  { log "WARNING" "$@"; }
log_error()    { log "ERROR" "$@"; }
log_critical() { log "CRITICAL" "$@"; }

# -----------------------------------------------------------------------------
# Items to include in modules.zip
# -----------------------------------------------------------------------------
ITEMS_TO_ZIP=(
    "booking"
    "vrbo"
    "hotelplanner"
    "vio"
    "general"
    "common"
    "holibob"
    "viator"
    "config.py"
)

require_command() {
    local command_name="$1"

    if ! command -v "${command_name}" > /dev/null 2>&1; then
        log_critical "Required command not found: ${command_name}"
        exit 1
    fi
}

validate_items() {
    local missing_items=0

    if [[ ! -d "${SOURCE_DIR}" ]]; then
        log_critical "Source directory not found: ${SOURCE_DIR}"
        return 1
    fi

    for item in "${ITEMS_TO_ZIP[@]}"; do
        local item_path="${SOURCE_DIR}/${item}"

        if [[ ! -e "${item_path}" ]]; then
            log_error "Missing item: ${item_path}"
            missing_items=1
        fi
    done

    if [[ "${missing_items}" -ne 0 ]]; then
        return 1
    fi

    return 0
}

create_zip() {
    mkdir -p "${OUTPUT_DIR}"
    rm -f "${ZIP_PATH}"

    log_info "Creating ${ZIP_PATH} from ${SOURCE_DIR}"

    for item in "${ITEMS_TO_ZIP[@]}"; do
        local item_path="${SOURCE_DIR}/${item}"

        if [[ -d "${item_path}" ]]; then
            # Keep folder names unchanged and skip Python cache files.
            (
                cd "${SOURCE_DIR}" &&
                zip -rq "${ZIP_PATH}" "${item}" -x "*.pyc" -x "*/__pycache__/*"
            )
        else
            # Keep file names unchanged, including extensions like .py.
            (
                cd "${SOURCE_DIR}" &&
                zip -q "${ZIP_PATH}" "${item}"
            )
        fi
    done

    log_info "Created zip archive at ${ZIP_PATH}"
}

extract_zip() {
    mkdir -p "${OUTPUT_DIR}"

    log_info "Extracting ${ZIP_PATH} into ${OUTPUT_DIR}"
    unzip -oq "${ZIP_PATH}" -d "${OUTPUT_DIR}"
    log_info "Extracted ${ZIP_NAME} into ${OUTPUT_DIR}"
}

package_items() {
    require_command "zip"
    require_command "unzip"

    log_info "Using source directory: ${SOURCE_DIR}"
    log_info "Using output directory: ${OUTPUT_DIR}"

    if ! validate_items; then
        log_critical "Packaging stopped because one or more ITEMS_TO_ZIP entries are missing"
        return 1
    fi

    create_zip
    extract_zip

    log_info "Packaging completed successfully"
    return 0
}

if ! package_items; then
    log_critical "Packaging encountered errors. Check log: ${LOG_FILE}"
    exit 1
fi

exit 0
