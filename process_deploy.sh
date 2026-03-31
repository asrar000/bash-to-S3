#!/bin/bash

# =============================================================================
# Processor Deployer Script
# Deploys specified files and zipped folders to S3 by:
# 1. Uploading individual files as specified
# 2. Creating a zip archive of specified folders and files
# 3. Uploading the zip archive to S3
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------
S3_BUCKET="${S3_BUCKET:-your-s3-bucket-name}"
S3_SCRIPTS_DIR="${S3_SCRIPTS_DIR:-your/s3/scripts/dir}"
S3_PREFIX="${S3_SCRIPTS_DIR}/processor"

# AWS Configuration
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# -----------------------------------------------------------------------------
# Directory Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"   # Two levels up from script
PROCESSOR_DIR="${ROOT_DIR}/processor"

# -----------------------------------------------------------------------------
# Logging Setup
# -----------------------------------------------------------------------------
CURRENT_DATE="$(date +%Y-%m-%d)"
CURRENT_DATETIME="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_DIR="${ROOT_DIR}/logs/deployer/${CURRENT_DATE}"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/rcron_processor_deployer_${CURRENT_DATETIME}.log"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "${timestamp} - processor_deployer - ${level} - ${message}" | tee -a "${LOG_FILE}"
}

log_info()    { log "INFO"     "$@"; }
log_warning() { log "WARNING"  "$@"; }
log_error()   { log "ERROR"    "$@"; }
log_critical(){ log "CRITICAL" "$@"; }

# -----------------------------------------------------------------------------
# Type 1 — Files to Upload Directly to S3 (no zipping)
# -----------------------------------------------------------------------------
FILES_TO_UPLOAD=(
    "requirements.txt"
    "install-requirements.sh"
    "booking_processor.py"
    "vrbo_processor.py"
    "hotelplanner_processor.py"
    "vio_processor.py"
    "holibob_processor.py"
    "general_processor.py"
    "viator_processor.py"
)

# -----------------------------------------------------------------------------
# Type 2 — Items to Bundle into a Zip, then Upload
# Format: ZIP_NAME and its corresponding ITEMS list
# -----------------------------------------------------------------------------
ZIP_NAME="modules.zip"
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

# -----------------------------------------------------------------------------
# Function: Upload a single file to S3
# -----------------------------------------------------------------------------
upload_file() {
    local local_path="$1"
    local s3_key="$2"

    if [[ ! -f "${local_path}" ]]; then
        log_error "File not found: ${local_path}"
        return 1
    fi

    log_info "Uploading ${local_path} to s3://${S3_BUCKET}/${s3_key}"

    if aws s3 cp "${local_path}" "s3://${S3_BUCKET}/${s3_key}" \
        --profile "${AWS_PROFILE}" \
        --region  "${AWS_REGION}"; then

        # Verify the upload succeeded
        if aws s3api head-object \
            --bucket "${S3_BUCKET}" \
            --key    "${s3_key}"    \
            --profile "${AWS_PROFILE}" \
            --region  "${AWS_REGION}" > /dev/null 2>&1; then
            log_info "Successfully uploaded ${s3_key}"
            return 0
        else
            log_error "Upload verification failed for ${s3_key}"
            return 1
        fi
    else
        log_error "Failed to upload ${local_path}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Function: Create a zip archive from specified items
# -----------------------------------------------------------------------------
create_zip() {
    local zip_name="$1"
    local temp_dir="$2"
    shift 2
    local items=("$@")

    local zip_path="${temp_dir}/${zip_name}"

    # Build zip: walk directories recursively, add files directly
    for item in "${items[@]}"; do
        local item_path="${PROCESSOR_DIR}/${item}"

        if [[ ! -e "${item_path}" ]]; then
            log_warning "Item not found, skipping: ${item_path}"
            continue
        fi

        if [[ -d "${item_path}" ]]; then
            # Add directory contents, preserving relative path from PROCESSOR_DIR
            (cd "${PROCESSOR_DIR}" && zip -r "${zip_path}" "${item}" -x "*.pyc" -x "*/__pycache__/*")
        else
            # Add individual file, preserving relative path from PROCESSOR_DIR
            (cd "${PROCESSOR_DIR}" && zip "${zip_path}" "${item}")
        fi
    done

    log_info "Created zip archive at ${zip_path}"
    echo "${zip_path}"
}