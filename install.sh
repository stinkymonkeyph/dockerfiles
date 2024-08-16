
#!/bin/sh

# exit if a command fails
set -eo pipefail

apk update

# install mysqldump
apk add mysql-client
apk add mariadb-connector-c

# install s3 tools
apk add python3 py3-pip
pip install awscli

# install curl for Discord notifications
apk add curl

# cleanup
rm -rf /var/cache/apk/*
