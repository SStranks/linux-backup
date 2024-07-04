# linux-backup

Automated scripts for backing up linux distro files and mongo databases from docker volumes

## IMPORTANT NOTE

The scripts contain hardcoded usernames, paths, and details unique to my setup. This repo is for proof of concept, if you wish to run them you must adjust as required.

## Requirements

- Scripts presume that docker is installed, along with a mongo database within a docker volume.
- Create .env file with MONGODB_USER and MONGODB_PASSWORD, to be consumed by the docker compose file for accessing the mongo database.

## Running the script

Run main.sh from ROOT; requires root to copy files from root folders during backup process.

### Overview of the process

The main script sets a location (default: /tmp) in to which backup files will be stored; /tmp is a good choice as these will be automatically erased on server reboot.

A sub-script (init.sh) is initialized, under the user where docker and the mongo DB volume is located. This process will then:

- check if a docker daemon is active and initializes if not.
- check if the docker container is active and initializes if not - the included docker compose file contains details of this standalone temporary mongo container, for the puroses of extracting the DB.
- check for the mongo DB container to be active and healthy
- executes 'monogodump.sh' script within the docker container; runs mongodump command to extract the DB, then compresses the DB into a tarball.
- Copy the tarball into the backup folder location.

Files from user accounts are copied into the backup folder using rsync; excludes various heavyweight and unnecessary folders e.g. .git, node_modules, dist, etc

Files from /etc and /root are copied into the backup folder using rsync.

All the sub-folders within the backup folder are then compressed into tarball files, followed by encryption with gpg aes256 cipher to ensure security of data.

An external drive is mounted to which the tarballs are then transferred to for storage - my setup is WSL2 based with no automatically mounted drives on boot for security. The drive is unmounted after transfer of files.
