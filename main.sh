#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# main.sh - WSL2 Linux Backup Script
#
# Description:
#   Backs up critical Linux system and user files, compresses and encrypts
#   the archives, and transfers them to a mounted Windows drive.
#
# Requirements:
#   - Bash v4+
#   - root user privileges (optional; if user wants to backup root files)
#   - Docker installed and configured for rootless operation (via `init.sh`)
#   - `gpg` installed for encryption
#   - `rsync` and `tar` for file operations
#   - Windows drive mount capability (`drvfs` under WSL2)
#
# Procedure:
#   1. Prompt for Linux backup directory
#   2. Run `init.sh` as the `dev1` user to dump MongoDB
#   3. Copy and archive specified user and system folders
#   4. Compress and encrypt the archives
#   5. Mount Windows drive and transfer encrypted files
#
# Author:      Simon Stranks
# Last Update: 2025-07-05
###############################################################################

#########################
#--- PROCEDURE START ---#
#########################

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
  if [ $exit_code -ne 0 ]; then
    # BASH_LINENO[0] is the line number where cleanup was called,
    # BASH_LINENO[1] is the line number where the function/script exited
    local line=${BASH_LINENO[0]}
    log "ERROR" "init.sh exited with code $exit_code at or near line $line"
  fi
}
trap 'exit_code=$?; cleanup $exit_code' EXIT

log "INFO" "WSL2 Linux Backup Script: Starting.."

# Determine if running as root
is_root="true"
if [[ $EUID -ne 0 ]]; then
  log "WARN" "Not running as root. System directories will be skipped"
  is_root="false"
fi


# Backup mongo database; user confirmation
while true; do
  read -er -p "Do you want to back up the MongoDB database? (Y/N): " -i "y" backup_mongo
  backup_mongo=${backup_mongo,,}

  case "$backup_mongo" in
    y | yes)
      log "INFO" "User opted to run MongoDB backup"

      # List users to choose the one with Docker + Mongo access
      log "INFO" "Available users on system:"
      mapfile -t available_users < <(awk -F: '($3 >= 1000) && ($7 !~ /nologin/) { print $1 }' /etc/passwd)
      for user in "${available_users[@]}"; do echo "- $user"; done

      while true; do
        read -er -p "Enter username to run init.sh (Docker + Mongo access): " selected_user
        if [[ " ${available_users[*]} " == *" $selected_user "* ]]; then
          log "INFO" "Running MongoDB backup via init.sh as user: $selected_user"
          su -c "source /home/$selected_user/Workspace/Projects/linux-backup/init.sh" - "$selected_user"
          mongodump_exitcode=$?
          if [[ $mongodump_exitcode -ne 0 ]]; then
            log "ERROR" "Mongo dump did not complete! Exitcode: $mongodump_exitcode"
            log "ERROR" "Exiting main.sh"
            exit 1
          fi
          break
        else
          echo "Invalid user. Please select from the list above."
        fi
      done
      break
      ;;
    n | no)
      log "INFO" "Skipping MongoDB backup per user input"
      break
      ;;
    *)
      echo "Invalid input. Please enter Y or N."
      ;;
  esac
done

# Select users to back up
mapfile -t available_users < <(ls /home)
log "INFO" "Available users: ${available_users[*]}"

selected_users=()
while true; do
  read -er -p "Enter a username to back up (or type 'done' to finish): " username
  if [[ "$username" == "done" ]]; then
    break
  elif [[ " ${available_users[*]} " =~ $username ]]; then
    selected_users+=("$username")
  else
    echo "Invalid username. Available users: ${available_users[*]}"
  fi
done

if [[ ${#selected_users[@]} -eq 0 ]]; then
  log "ERROR" "No valid users selected. Exiting."
  exit 1
fi

# Linux root folder to hold backup files; user confirmation
while true; do
  read -er -p "Please enter linux directory where backup folder will be created: " -i "/tmp" linux_dir
  linux_backup_dir="${linux_dir}/$(date +%F)-backup"
  read -er -p "Backup folder: ${linux_backup_dir} .Continue? (Y/N/Exit): " -i "y" confirm
  confirm=${confirm,,}

  case "$confirm" in
    yes | y)
      echo "Proceeding" && echo && mkdir -p "$linux_backup_dir" && echo "Folder created: ${linux_backup_dir}"
      break
      ;;
    no | n)
      continue
      ;;
    exit | e)
      echo "Exiting procedure"
      exit 0
      ;;
    *)
      echo "Invalid Option. Enter Y/N/Exit"
      ;;
  esac
done



# Copy files from sources
for user in "${selected_users[@]}"; do
  log "INFO" "Copying files of user: $user"
  rsync -ar --exclude={/.nvm,/.vscode-remote-containers,/.docker,/.npm,/.cache,/.config,/bin,/.local,/.vscode-server,/.vscode-oss-dev,/.console-ninja,**/node_modules,**/.git,**/dist} "/home/$user/" "${linux_backup_dir}/${user}/"
  log "INFO" "Files copied to ${linux_backup_dir}/${user} . Folder Size: $(du "${linux_backup_dir}/${user}" -sh | awk '{print $1}')"
done

# Copy root files if root
if [[ "$is_root" == true ]]; then
    log "INFO" "Copying files of /etc"
  rsync -ar /etc/ "${linux_backup_dir}/etc/"
  log "INFO" "Files copied to ${linux_backup_dir}/etc . Folder Size: $(du "${linux_backup_dir}/etc" -sh | awk '{print $1}')"

  log "INFO" "Copying files of /root"
  rsync -ar /root/ "${linux_backup_dir}"/root/
  log "INFO" "Files copied to ${linux_backup_dir}/root . Folder Size: $(du "${linux_backup_dir}/root" -sh | awk '{print $1}')"
fi



# Compress files to tar archive; user confirmation
while true; do
  read -er -p "Proceed with Tarball compression?: (Y/Exit)" -i "y" question_compression
  question_compression=${question_compression,,}

  case $question_compression in
    yes | y)
      echo "Proceeding with compression" && echo
      break
      ;;
    exit | e)
      echo "Exiting procedure"
      exit 0
      ;;
    *)
      echo "Invalid Option. Enter Y/Exit"
      ;;
  esac
done

# Compress files to tar archive
pre_compression_folder_size=$(du "$linux_backup_dir" -sh | awk '{print $1}')

for user in "${selected_users[@]}"; do
  log "INFO" "Compressing files: ${linux_backup_dir}/${user}: Begin"
  tar czf "${linux_backup_dir}/${user}.tgz" -C "${linux_backup_dir}/${user}" .
  log "INFO" "Compressing files: ${linux_backup_dir}/${user}: Completed"
done

if [[ "$is_root" == true ]]; then
  log "INFO" "Compressing files: ${linux_backup_dir}/root: Begin"
  tar czf "${linux_backup_dir}/root.tgz" -C "${linux_backup_dir}/root" .
  log "INFO" "Compressing files: ${linux_backup_dir}/root: Completed"
  log "INFO" "Compressing files: ${linux_backup_dir}/etc: Begin"
  tar czf "${linux_backup_dir}/etc.tgz" -C "${linux_backup_dir}/etc" .
  log "INFO" "Compressing files: ${linux_backup_dir}/etc: Completed"
fi

log "INFO" "All files compressed successfully"
log "INFO" "Pre-Compression size total: ${pre_compression_folder_size}"
log "INFO" "Post-Compression size total: $(du "${linux_backup_dir}"/sstranks87.tgz "${linux_backup_dir}"/dev1.tgz "${linux_backup_dir}"/root.tgz "${linux_backup_dir}"/etc.tgz -ch | grep total | awk '{print $1}')"



# Encrypt tar archives; user confirmation
while true; do
  read -er -p "Proceed with Tarball encryption(Y/Exit)" -i "y" question_encryption
  question_encryption=${question_encryption,,}

  case $question_encryption in
    yes | y)
      echo "Proceeding with encryption" && echo
      break
      ;;
    exit | e)
      echo "Exiting procedure"
      exit 0
      ;;
    *)
      echo "Invalid Option. Enter Y/Exit";
      ;;
  esac
done

# Encrypt tar archives
all_archives=()
for user in "${selected_users[@]}"; do
  all_archives+=("${linux_backup_dir}/${user}.tgz")
done

if [[ "$is_root" == true ]]; then
  all_archives+=("${linux_backup_dir}/root.tgz" "${linux_backup_dir}/etc.tgz" "${linux_backup_dir}/mongodb.tgz")
fi

log "INFO" "Encrypting tar archives with gpg: Begin"
for archive in "${all_archives[@]}"; do
  gpg --symmetric --cipher-algo aes256 "$archive"
done
log "INFO" "Encrypting tar archives with gpg: Completed"



# Mount windows drive; user confirmation
while true; do
  read -er -p "Windows Drive letter to mount: " -i "D" drive_letter
  drive_letter=${drive_letter,,}

  if [[ $drive_letter == [a-z] ]]; then
    break;
  else
    echo "Please provider a drive letter from a-z" && echo && continue
  fi
done

if mountpoint -q "/mnt/${drive_letter}"; then
  log "INFO" "/mnt/${drive_letter} is already mounted"
else
  # Mount windows drive; user confirmation
  while true; do
    read -er -p "Mount ${drive_letter^}: to /mnt/${drive_letter} .Continue? (Y/N/Exit): " -i "y" confirm

    case $confirm in
      yes | y)
        echo "Proceeding to mount drive" && echo
        break
        ;;
      exit | e)
        echo "Exiting procedure"
        exit 0
        ;;
      *)
        echo "Invalid Option. Enter Y/Exit"
        ;;
    esac
  done
  # Mount windows drive
  log "INFO" "Mounting /mnt/${drive_letter}: Begin"
  mkdir -p /mnt/"${drive_letter}"
  mount -t drvfs "${drive_letter^}: /mnt/${drive_letter}"
  log "INFO" "Mounting /mnt/${drive_letter}: Completed"
fi



# Confirm windows directory to hold backup files
while true; do
  read -er -p "Please enter windows directory where backup folder will be created: " -i "/Backups/Linux" windows_dir
  windows_backup_dir="${windows_dir}/$(date '+%Y_%m_%d')"
  read -er -p "Backup folder: ${drive_letter^}:${windows_backup_dir} .Continue? (Y/N/Exit): " -i "y" confirm
  confirm=${confirm,,}

  case "$confirm" in
    yes | y)
      echo "Proceeding" && echo && mkdir -p /mnt/"${drive_letter}"/"${windows_backup_dir}" && echo "Folder created: /mnt/${drive_letter}/${windows_backup_dir}"
      break
      ;;
    no | n)
      continue
      ;;
    exit | e)
      echo "Exiting procedure"
      exit 0
      ;;
    *)
      echo "Invalid Option. Enter Y/N/Exit"
      ;;
  esac
done



# Transfer encrypted archives to windows system; user confirmation
while true; do
  log "INFO" "Transfer of encrypted tar archives"
  log "INFO" "Files will be transferred from: ${linux_backup_dir}"
  log "INFO" "Files will be transferred to: /mnt/${drive_letter}/${windows_backup_dir}"
  read -er -p "Proceed with file transfer? (Y/Exit)" -i "y" question_transfer
  question_transfer=${question_transfer,,}

  case $question_transfer in
    yes | y)
      echo "Proceeding with file transfer" && echo
      break
      ;;
    exit | e)
      echo "Exiting procedure"
      exit 0
      ;;
    *)
      echo "Invalid Option. Enter Y/Exit";
      ;;

  esac
done

# Transfer encrypted archives to windows system
log "INFO" "Transferring files to /mnt/${drive_letter}/${windows_backup_dir}: Begin"
rsync -a "${linux_backup_dir}"/mongodb.tgz.gpg "${linux_backup_dir}"/sstranks87.tgz.gpg "${linux_backup_dir}"/dev1.tgz.gpg "${linux_backup_dir}"/root.tgz.gpg "${linux_backup_dir}"/etc.tgz.gpg /mnt/"${drive_letter}"/"${windows_backup_dir}"/
log "INFO" "Transferring files /mnt/${drive_letter}/${windows_backup_dir}: Completed"



# If root unmount drive; user confirmation
if [[ "$is_root" == true ]]; then
  while true; do
    read -er -p "Do you wish to unmount /mnt/${drive_letter}? (Y/N/Exit): " -i "y" confirm
    confirm=${confirm,,}

    case "$confirm" in
      yes | y)
        # Unmount windows drive
        log "INFO" "Unmounting /mnt/${drive_letter}: Begin"
        umount /mnt/"${drive_letter}" || {
          log "ERROR" "Failed to unmount /mnt/${drive_letter}"
          exit 1
        }
        log "INFO" "Unmounting /mnt/${drive_letter}: Completed"
        break
        ;;
      no | n)
        continue
        ;;
      exit | e)
        echo "Exiting procedure"
        exit 0
        ;;
      *)
        echo "Invalid Option. Enter Y/N/Exit"
        ;;
    esac
  done
fi



log "INFO" "WSL2 Linux Backup Script: Completed"
exit 0
