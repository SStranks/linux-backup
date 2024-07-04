#!/bin/bash
####################################
#
# Mongodump - Executed on container start
# Output: DB as BSON; compressed to .tgz
# Requires: Bash v4+
#
####################################

#### NOTES ####
#
#### NOTES ####


#########################
#--- PROCEDURE START ---#
#########################


# Create output dir
cd /tmp
[[ -d mongodb ]] || mkdir mongodb

# Export MongoDB as BSON data
mongodump --out=/tmp/mongodb --username=$MONGODB_USER --password=$MONGODB_PASSWORD >> /tmp/mongodump-$(date +%F).log 2>&1
if [ ! $? == "0" ] 
then echo "MongoDump failed"; exit 1
else echo "MongoDump success"
fi

# Compress
tar czf mongodb.tgz -C /tmp/mongodb .
if [ ! $? == "0" ] 
then echo "Compression failed"; exit 1
else echo "Compression success"
fi

exit 0
