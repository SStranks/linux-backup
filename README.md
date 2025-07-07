![Repository Banner](repo_banner.jpg)
![Shell](https://img.shields.io/badge/language-shell-blue)
![WSL2](https://img.shields.io/badge/Platform-WSL2-blueviolet)
![Last Commit](https://img.shields.io/github/last-commit/SStranks/linux-backup)
![Lint](https://github.com/SStranks/linux-backup/actions/workflows/lint.yml/badge.svg)

Automated scripts for backing up linux distro files and mongo databases from docker volumes

## 📋 Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Setup](#setup)
- [Usage](#usage)
- [Backup Process Overview](#backup-process-overview)
- [Limitations](#limitations)
- [License](#license)

---

## ✅ Features

- Automated backup of:
  - MongoDB databases in Docker volumes
  - User files and config from `/etc` and `/root`
- Docker container readiness checks
- Automated temporary decryption of docker secrets
- Data compression and GPG encryption
- Transfer to external drives (designed for WSL2)
- Cleanup and logging

---

## 🔧 Requirements

- Linux (tested under WSL2)
- Docker (rootless) installed and running
- A MongoDB instance running in a Docker container
- `rsync`, `gpg`, `tar` available on host
- SOPS installed on host

---

## ⚙️ Setup

1. Clone the repository.
2. Create a `.env` file at the root with the following contents:

   ```env
   MONGO_CONTAINER=container_name
   MONGO_LOCAL_PORT=27017
   MONGO_DOCKER_PORT=27017
   MONGO_PROTOCOL=localhost
   ```

3. It is highly recommended to encrypt all local secrets. SOPS was used in this project:
   [SOPS Github](https://github.com/getsops/sops)
   [SOPS Installation](https://github.com/getsops/sops/releases)
   Utilize the binaries appropriate to your system e.g. for WSL2 Ubuntu using apt (debian pkgs), 'amd64'

   NOTE: If you wish to manage your own secrets, you can amend the docker-compose.yml top-level secrets to point to your individual secret files.

   Create a `.secret.yml` file at the root with the following contents:

   ```yaml
   mongo_user_service: your_mongo_username
   mongo_password_service: your_mongo_password
   ```

4. Encrypt the .secret.yaml file in-place using SOPS.

   ```
   `sops -p <SUB_KEY_FINGERPRINT[E]> -d -i --input-type yaml ./.secret.yaml`
   ```

## 📝 Usage

Run the main script as root from the project root directory:

```bash
sudo ./main.sh
Running as root is required to access protected directories like /etc and /root.
```

NOTE: If you do not wish to backup root files the script can be run under normal privileges.

## 🔄 Backup Process Overview

Backup location defaults to /tmp (ephemeral on reboot).

Initializes init.sh as the user that owns the Docker and Mongo volume.

Performs the following:

Decrypts local secret file and creates individual docker secret files.

Starts a rootless Docker daemon if not running.

Starts MongoDB container if not running.

Waits for MongoDB container to be healthy.

Runs mongodump.sh inside container to dump the DB.

Compresses Mongo dump to .tar.gz.

Copies DB dump to backup folder.

Uses rsync to copy:

User files (excluding heavy folders like .git, node_modules, etc.)

/etc and /root folders

Compresses and encrypts all backup subfolders with GPG (AES256 cipher).

Mounts an external drive, copies encrypted backups, then unmounts the drive.

## ⚠️ Limitations

External drive mounting is static and may not suit all environments.

## 📝 License

MIT License — feel free to use and modify.
