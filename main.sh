#!/bin/bash
####################################
#
# Backup: Dev Files + System
# Run script from Root
# Requires: Bash v4+
#
####################################

#### NOTES ####
#
# /tmp folder clear on server shutdown
# paste from windows to nano: ctrl-shift-v
#
#### NOTES ####

#### IMPROVEMENTS TO IMPLEMENT ####
#
# Pass args to mongodb script/set defaults in that script
# Utilize arrays to store successful files / iterate through in subsequent steps instead of hardcoding paths
#
### IMPROVEMENTS ####


#########################
#--- PROCEDURE START ---#
#########################

echo "WSL2 Linux Backup Script v1 - SStranks87"

## Confirm user is ROOT
if [[ $EUID > 0 ]]
  then echo "Please run script as root"
  exit 1
fi

## Confirm linux root folder to hold backup files
while true; do
read -e -p "Please enter linux directory where backup folder will be created: " -i "/tmp" linux_dir
linux_backup_dir="${linux_dir}/$(date +%F)-backup"
read -p "Backup folder: ${linux_backup_dir} .Continue? (Y/N/Exit): " confirm
confirm=${confirm,,}

case $confirm in 
	yes | y) echo "Proceeding" && echo && mkdir $linux_backup_dir && echo "Folder created: ${linux_backup_dir}";
		break;;
	no | n) continue;;
	exit | e) echo "Exiting procedure";
		exit;;
	*) echo "Invalid Option. Enter Y/N/Exit";
		continue;;
esac
done


### MONGODB BACKUP 

# Switch to user where mongo and docker exist
su -c "source /home/dev1/Workspace/Projects/Templates/Docker/mongo-backup/init.sh" - dev1
mongodump_exitcode=$?
if [[ mongodump_exitcode -ne 0 ]]
then
  echo "Error. Mongo dump did not complete! Exitcode: $mongodump_exitcode"
  echo "Aborting backup process"
  exit 1
fi

### COPY FILES


# Copy files: mongodb
echo "Copying files of: mongodb"
cp /tmp/mongodb.tgz ${linux_backup_dir}/mongodb/
echo "Files copied to ${linux_backup_dir}/mongodb . Folder Size: $(du ${linux_backup_dir}/mongodb -sh | awk '{print $1}')"
echo


# Copy files of user: sstranks87
echo "Copying files of user: sstranks87"
rsync -ar --exclude={/.nvm,/.vscode-remote-containers,/.docker,/.npm,/.cache,/bin,/.local,/Projects/**/node_modules,/Projects/**/.git,/Projects/**/dist} /home/sstranks87/ ${linux_backup_dir}/sstranks87/
echo "Files copied to ${linux_backup_dir}/sstranks87 . Folder Size: $(du ${linux_backup_dir}/sstranks87 -sh | awk '{print $1}')"
echo

# Copy files of user: dev1
echo "Copying files of user: dev1"
rsync -ar --exclude={/.nvm,/.vscode-remote-containers,/.docker,/.npm,/.cache,/bin,/.local,/.vscode-server,/.vscode-oss-dev,/.console-ninja,/Workspace/Projects/**/node_modules,/Workspace/Projects/**/.git,/Workspace/Projects/**/dist} /home/dev1/ ${linux_backup_dir}/dev1/
echo "Files copied to ${linux_backup_dir}/dev1 . Folder Size: $(du ${linux_backup_dir}/dev1 -sh | awk '{print $1}')"
echo

# Copy files of /etc
echo "Copying files of /etc"
rsync -ar /etc/ ${linux_backup_dir}/etc/
echo "Files copied to ${linux_backup_dir}/etc . Folder Size: $(du ${linux_backup_dir}/etc -sh | awk '{print $1}')"
echo

# Copy files of /root
echo "Copying files of /root"
rsync -ar /root/ ${linux_backup_dir}/root/
echo "Files copied to ${linux_backup_dir}/root . Folder Size: $(du ${linux_backup_dir}/root -sh | awk '{print $1}')"
echo

echo "Total size of ${linux_backup_dir} : $(du $linux_backup_dir -sh | awk '{print $1}')"


### TAR COMPRESSION OF FILES


while true; do
read -e -p "Proceed with Tarball compression?: (Y/Exit)" -i "y" question_compression
question_compression=${question_compression,,}

case $question_compression in 
	yes | y) echo "Proceeding with compression" && echo;
		break;;
	exit | e) echo "Exiting procedure";
		exit;;
	*) echo "Invalid Option. Enter Y/Exit";
		continue;;

esac
done

pre_compression_folder_size=$(du $linux_backup_dir -sh | awk '{print $1}')

echo "Compressing files: ${linux_backup_dir}/sstranks87
tar czf ${linux_backup_dir}/sstranks87.tgz -C ${linux_backup_dir}/sstranks87 .
echo "Files compressed successfully" && echo

echo "Compressing files: ${linux_backup_dir}/dev1
tar czf ${linux_backup_dir}/dev1.tgz -C ${linux_backup_dir}/dev1 .
echo "Files compressed successfully" && echo

echo "Compressing files: ${linux_backup_dir}/root
tar czf ${linux_backup_dir}/root.tgz -C ${linux_backup_dir}/root .
echo "Files compressed successfully" && echo

echo "Compressing files: ${linux_backup_dir}/etc
tar czf ${linux_backup_dir}/etc.tgz -C ${linux_backup_dir}/etc .
echo "Files compressed successfully" && echo

echo "All files compressed successfully"
echo "Pre-Compression size total: ${pre_compression_folder_size}"
echo "Post-Compression size total: $(du ${linux_backup_dir}/sstranks87.tgz ${linux_backup_dir}/dev1.tgz ${linux_backup_dir}/root.tgz ${linux_backup_dir}/etc.tgz -ch | grep total | awk '{print $1}')


### ENCRYPT FILES WITH GPG


while true; do
read -e -p "Proceed with Tarball encryption(Y/Exit)" -i "y" question_encryption
question_encryption=${question_encryption,,}

case $question_encryption in 
	yes | y) echo "Proceeding with encryption" && echo;
		break;;
	exit | e) echo "Exiting procedure";
		exit;;
	*) echo "Invalid Option. Enter Y/Exit";
		continue;;

esac
done

gpg --symmetric --cipher-algo aes256 ${linux_backup_dir}/mongodb.tgz
gpg --symmetric --cipher-algo aes256 ${linux_backup_dir}/sstranks87.tgz
gpg --symmetric --cipher-algo aes256 ${linux_backup_dir}/dev1.tgz
gpg --symmetric --cipher-algo aes256 ${linux_backup_dir}/root.tgz
gpg --symmetric --cipher-algo aes256 ${linux_backup_dir}/etc.tgz
echo "All files encrypted successfully" && echo


### MOUNT EXTERNAL DRIVE


while true; do
read -e -p "Windows Drive letter to mount: " -i "D" drive_letter
drive_letter=${drive_letter,,}
if [[ $drive_letter == [a-z] ]]
then break
else echo "Please provider a drive letter from a-z" && echo && continue
fi
done

while true; do
read -p "Mount ${drive_letter^}: to /mnt/${drive_letter} .Continue? (Y/N/Exit): " question_mount_confirm

case $question_mount_confirm in 
	yes | y) echo "Proceeding to mount drive" && echo;
		break;;
	exit | e) echo "Exiting procedure";
		exit;;
	*) echo "Invalid Option. Enter Y/Exit";
		continue;;

esac
done

mount -t drvfs ${drive_letter^}: /mnt/${drive_letter}
echo "Drive mounted successfully"

## Confirm windows directory to hold backup files
while true; do
read -e -p "Please enter windows directory where backup folder will be created: " -i "/Linux/Backups" windows_dir
windows_backup_dir="${windows_dir}/$(date +%F)"
read -p "Backup folder: ${drive_letter^}:${windows_backup_dir} .Continue? (Y/N/Exit): " confirm
confirm=${confirm,,}

case $confirm in 
	yes | y) echo "Proceeding" && echo && mkdir /mnt/${driver_letter}/$windows_backup_dir && echo "Folder created: /mnt/${driver_letter}/$windows_backup_dir";
		break;;
	no | n) continue;;
	exit | e) echo "Exiting procedure";
		exit;;
	*) echo "Invalid Option. Enter Y/N/Exit";
		continue;;
esac
done


### TRANSFER ENCRYPTED ARCHIVES

while true; do
echo "Initiating transfer of encrypted tarballs"
echo "Files will be transferred from: ${linux_backup_dir}"
echo "Files will be transferred to: /mnt/${driver_letter}/$windows_backup_dir"
read -e -p "Proceed with file transfer? (Y/Exit)" -i "y" question_transfer
question_transfer=${question_transfer,,}

case $question_transfer in 
	yes | y) echo "Proceeding with file transfer" && echo;
		break;;
	exit | e) echo "Exiting procedure";
		exit;;
	*) echo "Invalid Option. Enter Y/Exit";
		continue;;

esac
done

echo "Transferring files"
rsync -a ${linux_backup_dir}/mongodb.tgz.gpg ${linux_backup_dir}/sstranks87.tgz.gpg ${linux_backup_dir}/dev1.tgz.gpg ${linux_backup_dir}/root.tgz.gpg ${linux_backup_dir}/etc.tgz.gpg /mnt/${driver_letter}/$windows_backup_dir/
echo "Transfer successful"
echo


### UNMOUNT EXTERNAL DRIVE

echo "Unmounting windows drive"
umount /mnt/${drive_letter}
echo "Drive unmounted successfully"

### REMOVE LINUX FILES

# Assuming default (/tmp) is used, these are deleted on server shutdown
# Could implement RAMDisk storage for procedure instead?

echo "Backup procedure completed"
echo "Backup procedure exiting"
