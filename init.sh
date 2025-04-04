#!/bin/bash
####################################
#
# MongoDB Backup Script
# Output: DB as BSON; compressed to .tgz
# Run from: Root
# Requires: Bash v4+
#
####################################

#### NOTES ####
#
# 2>&1    2 is STDERR, 1 is STDOUT. Pipes error to stdout
# >/dev/null    This discards any input that is written to it
# [ ! -z "$process2" ] && echo "Not null"   Checks if variable is not null
# ||    OR; executes if left operand returned error
# &&    AND; executes if left executed successfully
# &   execute the preceding statement in the background.
# ;   execute the preceding statement and, after it completes, proceed to the next statement.
# |   execute the preceding statement and connect its stdout the to stdin of the statement which follows.
#
# NOTE_1: "echo 'db.runCommand(\"ping\").ok' | mongosh --quiet" - this produced mongosh prompt itself, not just stdout
#
# return 1 2> /dev/null || exit 1 <-- this passes error up to calling script, or exits, depending on how script is invoked.
#
#### NOTES ####


#########################
#--- PROCEDURE START ---#
#########################

docker_container=backup-mongo-db
docker_compose_yml=/home/dev1/Workspace/Projects/linux-backup/docker-compose.yml

# Initialize Docker Daemon (Rootless) if not already active
if ! curl -s --unix-socket /home/dev1/.docker/run/docker.sock http/_ping 2>&1 >/dev/null
then dockerd-rootless.sh & docker_daemon=$!
fi


# Wait for Docker Daemon to finish initialization
for i in {1..5}
do
  # Daemon returns OK or null
  if curl -s --unix-socket /home/dev1/.docker/run/docker.sock http/_ping 2>&1 >/dev/null
  then
    echo "Docker Daemon is Running"
    break
  else
    if [ $i -eq 5 ] 
    then echo "Error: Daemon not active"
      if [ -n "$docker_daemon" ]; then kill -9 $docker_daemon; 
      echo "Process 1 terminated"; 
      return 1 2> /dev/null || exit 1
      fi
    fi
    echo "Docker Daemon is Not Running"
    sleep 1
  fi
done


# Check if container exists
docker container inspect $docker_container > /dev/null 2>&1
if [[ $? -eq 0 ]]
then
  echo "Container $docker_container exists"
  # Check if container is running
  if [ $(docker container inspect -f '{{.State.Running}}' $docker_container) == "true" ] 
  then echo "Container is already running";
  else echo "Container is not running. Starting"; docker container start $docker_container
  fi
else 
  echo "Container $docker_container does not exist. Starting compose file"; 
  docker compose -f $docker_compose_yml up -d
fi


# Wait for MongoDB service ready
for i in {1..5}
do
  # See NOTE_1
  mongodb_ping_status=$(docker exec $docker_container sh -c "mongosh --quiet --eval \"db.runCommand('ping').ok\"")
  if [ "$mongodb_ping_status" == "1" ]
  then
    echo "MongoDB active"; break
  else
    if [ $i -eq 5 ] 
    then echo "Error: MongoDB not active"
      docker container stop $docker_container
      wait
      if [ -n "$docker_daemon" ]; then kill -9 $docker_daemon; echo "Process 1 terminated"; fi
      return 1 2> /dev/null || exit 1
    fi 
    echo "MongoDB not ready. Trying again in 2 seconds.."
    sleep 2
  fi
done


# Run MongoDump to export all database as BSON
docker exec $docker_container /tmp/mongodump.sh
wait $!

# Copy tar data
docker cp $docker_container:/tmp/mongodb.tgz /tmp

# Cleanup Processes
docker container stop $docker_container
wait $!
kill -9 $docker_daemon
wait $!
return 0 2> /dev/null || exit 0
