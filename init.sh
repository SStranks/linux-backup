#!/usr/bin/env bash
set -euo pipefail

################################################################################
# MongoDB Backup Script
#
# Description:
#   Performs a full MongoDB database backup inside a Docker container using
#   `mongodump`, compresses the output into a `.tgz` archive, and saves it to
#   the host machine. Designed to be run from the project root.
#
# Requirements:
#   - Bash v4+
#   - Docker (rootless setup)
#   - Docker Compose v2
#
# Outputs:
#   - Compressed MongoDB dump archive (BSON) at /tmp/mongodb.tgz
#
# Usage:
#   - Sourced in main.sh
#
################################################################################

#########################
#--- PROCEDURE START ---#
#########################

SECRETS_SCRIPT="./secrets.sh"
DOCKER_CONTAINER_MONGO=$MONGO_CONTAINER
DOCKER_COMPOSE_YML="/home/$USER/Workspace/Projects/linux-backup/docker-compose.yml"
LOG_FILE="./logs_$(date +%F).log"

log() {
  local log_level="$1"
  local message="$2"
  local script_name
  script_name="$(basename "$0")"
  local timestamp
  timestamp=$(date +%F_%H-%M-%S)
  echo "$timestamp [$log_level] [$script_name] $message" | tee -a "$LOG_FILE"
}

cleanup() {
  local exit_code="$1"
  if [ "$exit_code" -ne 0 ]; then
    # BASH_LINENO[0] is the line number where cleanup was called,
    # BASH_LINENO[1] is the line number where the function/script exited
    local line=${BASH_LINENO[0]}
    log "ERROR" "init.sh exited with code $exit_code at or near line $line"
  fi

  # Cleanup secrets from secrets.sh
  if [[ -d "${SECRET_PATH:-}" ]]; then
    log "INFO" "Cleaning up secrets at $SECRET_PATH"
    find "$SECRET_PATH" -type f -name '.secret.*.txt' -delete
  fi

  docker container stop "$DOCKER_CONTAINER_MONGO" || true
  [[ -n "${DOCKER_DAEMON:-}" ]] && kill -9 "$DOCKER_DAEMON" || true
}
trap 'exit_code=$?; cleanup $exit_code' EXIT



# Set env variables
if [[ -f ./.env ]]; then
  set -a && source ./.env && set +a
else
  log "ERROR" "Missing .env file"
  exit 1
fi



# Export decrypted secrets to individual secret files
if [[ -x "$SECRETS_SCRIPT" ]]; then
  log "INFO" "Running secrets script: $SECRETS_SCRIPT"
  "$SECRETS_SCRIPT"
else
  log "ERROR" "Secrets script not found or not executable: $SECRETS_SCRIPT"
  exit 1
fi



# Get Docker rootless socket
if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/docker.sock" ]]; then
  DOCKER_ROOTLESS_SOCKET="$XDG_RUNTIME_DIR/docker.sock"
elif [[ -S "$HOME/.docker/run/docker.sock" ]]; then
  DOCKER_ROOTLESS_SOCKET="$HOME/.docker/run/docker.sock"
elif [[ -S "/run/user/$(id -u)/docker.sock" ]]; then
  DOCKER_ROOTLESS_SOCKET="/run/user/$(id -u)/docker.sock"
else
  log "INFO" "Error: Could not locate a Docker rootless socket"
  exit 1
fi


# Initialize Docker Daemon (rootless) if not already active
if ! curl -s --unix-socket "$DOCKER_ROOTLESS_SOCKET" http://localhost/_ping >/dev/null 2>&1; then
  if systemctl --user is-active --quiet docker; then
    log "INFO" "Docker socket exists but not responsive; restarting.."
    systemctl --user restart docker
  else
    log "INFO" "Docker rootless not running; starting.."
    systemctl --user start docker || {
      log "INFO" "systemd docker start failed; attempting manual dockerd-rootless.sh initialization.."
      dockerd-rootless.sh >/dev/null 2>&1 &
      DOCKER_DAEMON=$!
    }
  fi
fi


# Wait for Docker Rootless Daemon to initialize
for i in {1..5}
do
  # Daemon returns OK or null
  if curl -s --unix-socket "$DOCKER_ROOTLESS_SOCKET" http://localhost/_ping >/dev/null 2>&1; then
    log "INFO" "Docker Rootless Daemon: Active"
    break
  else
    if [[ $i -eq 5 ]]; then
      log "ERROR" "Docker Rootless Daemon: not found or started"
      return 1 2> /dev/null || exit 1
    fi
    log "INFO" "Docker Rootless Daemon: Inactive"
    log "INFO" "Docker Rootless Daemon: Waiting for 1 second.."
    sleep 1
  fi
done


# Check if container exists
if docker container inspect "$DOCKER_CONTAINER_MONGO" > /dev/null 2>&1; then
  log "INFO" "Container $DOCKER_CONTAINER_MONGO: exists"
  # Check if container is running
  if [[ $(docker container inspect -f '{{.State.Running}}' "$DOCKER_CONTAINER_MONGO") == "false" ]]; then
    log "INFO" "Container $DOCKER_CONTAINER_MONGO: is not running. Starting..";
    docker container start "$DOCKER_CONTAINER_MONGO";
  fi
else
  log "INFO" "Container $DOCKER_CONTAINER_MONGO: doesn't exist. Starting compose file..";
  docker compose -f "$DOCKER_COMPOSE_YML" up -d;
fi


# Wait for docker container to reach "running" state
echo "Waiting for container $DOCKER_CONTAINER_MONGO to be running..."
for i in {1..10}; do
  state=$(docker container inspect -f '{{.State.Running}}' "$DOCKER_CONTAINER_MONGO" 2>/dev/null || echo "false")
  if [[ "$state" == "true" ]]; then
    log "INFO" "Container $DOCKER_CONTAINER_MONGO: is running"
    break
  fi

  if [[ $i -eq 10 ]]; then
    log "ERROR" "Container $DOCKER_CONTAINER_MONGO did not start after 10 seconds"
    exit 1
  fi

  log "INFO" "Container $DOCKER_CONTAINER_MONGO: not running yet. Retrying in 1 second..."
  sleep 1
done


# Check presence of mongosh in container
docker exec "$DOCKER_CONTAINER_MONGO" sh -c "command -v mongosh >/dev/null 2>&1" || {
  log "ERROR" "Error: mongosh is not installed in the Mongo container."
  exit 1
}


# Wait for MongoDB service ready
for i in {1..5}
do
  # // NOTE:  echo 'db.runCommand(\"ping\").ok' | mongosh --quiet" - this produced mongosh prompt itself, not just stdout
  mongodb_ping_status=$(docker exec "$DOCKER_CONTAINER_MONGO" sh -c "mongosh --quiet --eval \"db.runCommand('ping').ok\"")
  if [[ "$mongodb_ping_status" == "1" ]]; then
    log "INFO" "Mongo service active";
    break;
  else
    if [[ $i -eq 5 ]]; then
      log "ERROR" "Mongo service not active"
      docker container stop "$DOCKER_CONTAINER_MONGO"
      wait
      return 1 2> /dev/null || exit 1
    fi
    log "INFO" "Mongo service not ready. Trying again in 2 seconds.."
    sleep 2
  fi
done


# Run mongodump.sh in container to export all databases as BSON
ARCHIVE_PATH=$(docker exec "$DOCKER_CONTAINER_MONGO" timeout 120 /tmp/mongodump.sh | tail -n 1)
if [[ -z "$ARCHIVE_PATH" ]]; then
  log "ERROR" "mongodump.sh failed or returned no output"
  exit 1
fi

# Copy tar data
docker cp "$DOCKER_CONTAINER_MONGO":"$ARCHIVE_PATH" /tmp

log "INFO" "init.sh completed successfully"
return 0 2> /dev/null || exit 0
