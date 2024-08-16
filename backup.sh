
#!/bin/sh

set -eo pipefail

notify_discord () {
  SUCCESS_MSG=$1
  FAIL_MSG=$2

  if [ "${DISCORD_WEBHOOK_URL}" != "**None**" ]; then
    # Construct the JSON payload
    JSON_PAYLOAD=$(cat <<EOF
{
  "embeds": [
    {
      "title": "DB Backup to S3 Notification",
      "color": 3066993,
      "fields": [
        {
          "name": "Success",
          "value": "$SUCCESS_MSG",
          "inline": false
        },
        {
          "name": "Fail",
          "value": "$FAIL_MSG",
          "inline": false
        }
      ],
      "footer": {
        "text": "Backup completed at $(date +'%Y-%m-%d %H:%M:%S')"
      }
    }
  ]
}
EOF
)

    # Send the notification
    curl -H "Content-Type: application/json" -X POST -d "$JSON_PAYLOAD" $DISCORD_WEBHOOK_URL
  else
    echo "Discord Webhook URL is not set. Skipping notification."
  fi
}
# Initial checks and variable setups...

MYSQL_HOST_OPTS="-h $MYSQL_HOST -P $MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD"
DUMP_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
DATABASES_BACKED_UP=""
DATABASES_FAILED=""

copy_s3 () {
  SRC_FILE=$1
  DEST_FILE=$2

  if [ "${S3_ENDPOINT}" == "**None**" ]; then
    AWS_ARGS=""
  else
    AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
  fi

  if [ "${S3_ENSURE_BUCKET_EXISTS}" != "no" ]; then
    echo "Ensuring S3 bucket $S3_BUCKET exists"
    EXISTS_ERR=`aws $AWS_ARGS s3api head-bucket --bucket "$S3_BUCKET" 2>&1 || true`
    if [[ ! -z "$EXISTS_ERR" ]]; then
      echo "Bucket $S3_BUCKET not found (or owned by someone else), attempting to create"
      aws $AWS_ARGS s3api create-bucket --bucket $S3_BUCKET
    fi
  fi

  echo "Uploading ${DEST_FILE} on S3..."
  
  cat $SRC_FILE | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/$DEST_FILE

  if [ $? != 0 ]; then
    >&2 echo "Error uploading ${DEST_FILE} on S3"
    return 1
  else
    rm $SRC_FILE
    return 0
  fi
}

# MySQL dump logic...

for DB in $DATABASES; do
  echo "Creating individual dump of ${DB} from ${MYSQL_HOST}..."

  DUMP_FILE="/tmp/${DB}.sql.gz"
  mysqldump $MYSQL_HOST_OPTS $MYSQLDUMP_OPTIONS --databases $DB | gzip > $DUMP_FILE

  if [ $? == 0 ]; then
    if [ "${S3_FILENAME}" == "**None**" ]; then
      S3_FILE="${DUMP_START_TIME}.${DB}.sql.gz"
    else
      S3_FILE="${S3_FILENAME}.${DB}.sql.gz"
    fi

    if copy_s3 $DUMP_FILE $S3_FILE; then
      DATABASES_BACKED_UP="${DATABASES_BACKED_UP}\n- ${DB}"
    else
      DATABASES_FAILED="${DATABASES_FAILED}\n- ${DB}"
    fi
  else
    DATABASES_FAILED="${DATABASES_FAILED}\n- ${DB}"
    >&2 echo "Error creating dump of ${DB}"
  fi
done

# Final notification with styled message
if [ -z "$DATABASES_BACKED_UP" ]; then
  DATABASES_BACKED_UP="None"
fi

if [ -z "$DATABASES_FAILED" ]; then
  DATABASES_FAILED="None"
fi

notify_discord "$DATABASES_BACKED_UP" "$DATABASES_FAILED"

echo "SQL backup finished"
