#!/usr/bin/env bash
set -euo pipefail

################################################################################
# MongoDB Dump Script
#
# Description:
#   Runs `mongodump` inside the MongoDB container to export all databases as BSON,
#   stores the output in a timestamped folder under /tmp, and compresses it into 
#   a `.tgz` archive.
#
# Usage:
#   This script is intended to be run automatically when the MongoDB container 
#   starts; called from init.sh
#
# Requirements:
#   - Bash v4+
#   - Docker secrets: 
#       /run/secrets/mongodb_user
#       /run/secrets/mongodb_password
#
# Output:
#   - Compressed BSON archive: /tmp/mongodb_YYYY-MM-DD_HH-MM-SS.tgz
#   - Dump log: {MONGO_CONTAINER}:/tmp/mongodump_YYYY-MM-DD.log
#
################################################################################

#########################
#--- PROCEDURE START ---#
#########################

TIMESTAMP="$(date +%F_%H-%M-%S)"

OUTPUT_DIR="/tmp/mongo_$TIMESTAMP"
ARCHIVE_PATH="/tmp/mongodb_$TIMESTAMP.tgz"
LOG_FILE="/tmp/mongodump_$(date +%F).log"

MONGO_USER="$(cat /run/secrets/mongo_user_service)"
MONGO_PASSWORD="$(cat /run/secrets/mongo_password_service)"

log() {
    local log_level="$1"
    local message="$2"
    local script_name
    script_name="$(basename "$0")"
    local timestamp
    timestamp=$(date +%F_%H-%M-%S)
    echo "$timestamp [$log_level] [$script_name] $message" | tee -a "$LOG_FILE"
}

[[ -f /run/secrets/mongo_user_service ]] || { log "ERROR" "Missing mongo_user_service secret"; exit 1; }
[[ -f /run/secrets/mongo_password_service ]] || { log "ERROR" "Missing mongo_password_service secret"; exit 1; }
[[ -z "${MONGO_PROTOCOL:-}" ]] && { log "ERROR" "MONGO_PROTOCOL not set"; exit 1; }
[[ -z "${MONGO_LOCAL_PORT:-}" ]] && { log "ERROR" "MONGO_LOCAL_PORT not set"; exit 1; }

log "INFO" "[$(date)] Starting MongoDB dump..."

# Create output dir
mkdir -p "$OUTPUT_DIR"

# Export MongoDB as BSON
if mongodump \
  --host="$MONGO_PROTOCOL" \
  --port="$MONGO_LOCAL_PORT" \
  --authenticationDatabase=admin \
  --username="$MONGO_USER" \
  --password="$MONGO_PASSWORD" \
  --out="$OUTPUT_DIR" \
  --quiet >> "$LOG_FILE" 2>&1; then
  log "INFO" "MongoDump succeeded"
else
  log "ERROR" "MongoDump failed"
  exit 1
fi

# Compress output to .tgz
if tar czf "$ARCHIVE_PATH" -C "$OUTPUT_DIR" .; then
  log "INFO" "Compression succeeded"
else
  log "ERROR" "Compression failed"
  exit 1
fi

log "INFO" "[$(date)] MongoDB dump and compression complete."

# Echo the archive path so the caller can capture it
echo "$ARCHIVE_PATH"

exit 0
