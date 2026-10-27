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

: "${MONGO_PROTOCOL:?MONGO_PROTOCOL variable is required}"
: "${MONGO_LOCAL_PORT:?MONGO_LOCAL_PORT variable is required}"

mongo_user="$(cat /run/secrets/mongo_user_service)"
mongo_password="$(cat /run/secrets/mongo_password_service)"

: "${mongo_user:?mongo_user_service is empty}"
: "${mongo_password:?mongo_password_service is empty}"

timestamp="$(date +%F_%H-%M-%S)" && readonly timestamp
output_dir="/tmp/mongo_$timestamp"
archive_path="/tmp/mongodb_$timestamp.tgz"
log_file="/tmp/mongodump_$(date +%F).log"

log() {
  local log_level="$1"
  local message="$2"
  local script_name
  local timestamp

  script_name="$(basename "$0")"
  timestamp=$(date +%F_%H-%M-%S)

  echo "$timestamp [$log_level] [$script_name] $message" | tee -a "$log_file"
}

log "INFO" "[$(date)] Starting MongoDB dump..."

# create output dir
if ! mkdir -p "$output_dir"; then
  log "ERROR" "could not create directory path: ${output_dir}"
  exit 1
fi

# export MongoDB as BSON
if mongodump \
  --host="$MONGO_PROTOCOL" \
  --port="$MONGO_LOCAL_PORT" \
  --authenticationDatabase=admin \
  --username="$mongo_user" \
  --password="$mongo_password" \
  --out="$output_dir" \
  --quiet >> "$log_file" 2>&1; then
  log "INFO" "MongoDump succeeded"
else
  log "ERROR" "MongoDump failed"
  exit 1
fi

# compress output to .tgz
if tar czf "$archive_path" -C "$output_dir" .; then
  log "INFO" "Compression succeeded"
else
  log "ERROR" "Compression failed"
  exit 1
fi

log "INFO" "[$(date)] MongoDB dump and compression complete."

# echo the archive path so the caller can capture it
echo "$archive_path"

exit 0
