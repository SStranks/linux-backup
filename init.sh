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

: "${MONGO_CONTAINER:?MONGO_CONTAINER variable is required}"

docker_container_mongo="$MONGO_CONTAINER"
project_dir=$(pnpm -w exec pwd)
secrets_script="${project_dir}/secrets.sh"
docker_compose_yml="${project_dir}/docker-compose.yml"
log_file="${project_dir}/logs_$(date +%F).log" && readonly log_file

log() {
  local log_level="$1"
  local message="$2"
  local script_name
  local timestamp

  script_name="$(basename "$0")"
  timestamp=$(date +%F_%H-%M-%S)

  echo "$timestamp [$log_level] [$script_name] $message" | tee -a "$log_file"
}

cleanup() {
  local exit_code="$1"

  if [[ "$exit_code" -ne 0 ]]; then
    local line=${BASH_LINENO[0]}
    log "ERROR" "init.sh exited with code $exit_code at or near line $line"
  fi

  # cleanup secrets from secrets.sh
  if [[ -d "${SECRET_PATH:-}" ]]; then
    log "INFO" "Cleaning up secrets at $SECRET_PATH"
    find "$SECRET_PATH" -type f -name '.secret.*.txt' -delete
  fi

  docker container stop "$docker_container_mongo" || true
  [[ -n "${DOCKER_DAEMON:-}" ]] && kill -9 "$DOCKER_DAEMON" || true
}
trap 'exit_code=$?; cleanup $exit_code' EXIT

# set env variables
if [[ -f "${project_dir}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a && source "${project_dir}/.env" && set +a
else
  log "ERROR" "Missing .env file"
  exit 1
fi

# export decrypted secrets to individual secret files
if [[ -x "$secrets_script" ]]; then
  log "INFO" "Running secrets script: $secrets_script"
  "$secrets_script"
else
  log "ERROR" "Secrets script not found or not executable: $secrets_script"
  exit 1
fi

# get Docker rootless socket
if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/docker.sock" ]]; then
  docker_rootless_socket="$XDG_RUNTIME_DIR/docker.sock"
elif [[ -S "$HOME/.docker/run/docker.sock" ]]; then
  docker_rootless_socket="$HOME/.docker/run/docker.sock"
elif [[ -S "/run/user/$(id -u)/docker.sock" ]]; then
  docker_rootless_socket="/run/user/$(id -u)/docker.sock"
else
  log "INFO" "Error: Could not locate a Docker rootless socket"
  exit 1
fi

# initialize Docker Daemon (rootless) if not already active
if ! curl -s --unix-socket "$docker_rootless_socket" http://localhost/_ping > /dev/null 2>&1; then
  if systemctl --user is-active --quiet docker; then
    log "INFO" "Docker socket exists but not responsive; restarting.."
    systemctl --user restart docker
  else
    log "INFO" "Docker rootless not running; starting.."
    systemctl --user start docker || {
      log "INFO" "systemd docker start failed; attempting manual dockerd-rootless.sh initialization.."
      dockerd-rootless.sh > /dev/null 2>&1 &
      DOCKER_DAEMON=$!
    }
  fi
fi

# wait for Docker Rootless Daemon to initialize
for i in {1..5}; do
  # Daemon returns OK or null
  if curl -s --unix-socket "$docker_rootless_socket" http://localhost/_ping > /dev/null 2>&1; then
    log "INFO" "Docker Rootless Daemon: Active"
    break
  else
    if [[ $i -eq 5 ]]; then
      log "ERROR" "Docker Rootless Daemon: not found or started"
      return 1 2> /dev/null
    fi
    log "INFO" "Docker Rootless Daemon: Inactive"
    log "INFO" "Docker Rootless Daemon: Waiting for 1 second.."
    sleep 1
  fi
done

# check if container exists
if docker container inspect "$docker_container_mongo" > /dev/null 2>&1; then
  log "INFO" "Container $docker_container_mongo: exists"
  # check if container is running
  if [[ $(docker container inspect -f '{{.State.Running}}' "$docker_container_mongo") == "false" ]]; then
    log "INFO" "Container $docker_container_mongo: is not running. Starting.."
    docker container start "$docker_container_mongo"
  fi
else
  log "INFO" "Container $docker_container_mongo: doesn't exist. Starting compose file.."
  docker compose -f "$docker_compose_yml" up -d
fi

# wait for docker container to reach "running" state
echo "Waiting for container $docker_container_mongo to be running..."
for i in {1..10}; do
  state=$(docker container inspect -f '{{.State.Running}}' "$docker_container_mongo" 2> /dev/null || echo "false")
  if [[ "$state" == "true" ]]; then
    log "INFO" "Container $docker_container_mongo: is running"
    break
  fi

  if [[ $i -eq 10 ]]; then
    log "ERROR" "Container $docker_container_mongo did not start after 10 seconds"
    exit 1
  fi

  log "INFO" "Container $docker_container_mongo: not running yet. Retrying in 1 second..."
  sleep 1
done

# check presence of mongosh in container
docker exec "$docker_container_mongo" sh -c "command -v mongosh >/dev/null 2>&1" || {
  log "ERROR" "Error: mongosh is not installed in the Mongo container."
  exit 1
}

# wait for MongoDB service ready
for i in {1..5}; do
  # // NOTE:  echo 'db.runCommand(\"ping\").ok' | mongosh --quiet" - this produced mongosh prompt itself, not just stdout
  mongodb_ping_status=$(docker exec "$docker_container_mongo" sh -c "mongosh --quiet --eval \"db.runCommand('ping').ok\"")
  if [[ "$mongodb_ping_status" == "1" ]]; then
    log "INFO" "Mongo service active"
    break
  else
    if [[ $i -eq 5 ]]; then
      log "ERROR" "Mongo service not active"
      docker container stop "$docker_container_mongo"
      wait
      return 1 2> /dev/null
    fi
    log "INFO" "Mongo service not ready. Trying again in 2 seconds.."
    sleep 2
  fi
done

# run mongodump.sh in container to export all databases as BSON
archive_path=$(docker exec "$docker_container_mongo" timeout 120 /tmp/mongodump.sh | tail -n 1)

if [[ -z "$archive_path" ]]; then
  log "ERROR" "mongodump.sh failed or returned no output"
  exit 1
fi

# copy tar data
docker cp "$docker_container_mongo":"$archive_path" /tmp

log "INFO" "init.sh completed successfully"
return 0 2> /dev/null
