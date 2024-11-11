#!/bin/bash

# Bot token
while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
    if [[ $tk == $'\0' ]]; then
        echo "Invalid input. Token cannot be empty."
        unset tk
    fi
done

# Chat id
while [[ -z "$chatid" ]]; do
    echo "Chat id: "
    read -r chatid
    if [[ $chatid == $'\0' ]]; then
        echo "Invalid input. Chat id cannot be empty."
        unset chatid
    elif [[ ! $chatid =~ ^\-?[0-9]+$ ]]; then
        echo "${chatid} is not a number."
        unset chatid
    fi
done

# Caption
echo "Caption (for example, your domain, to identify the database file more easily): "
read -r caption

# Cronjob
while true; do
    echo "Cronjob (minutes and hours) (e.g : 30 6 or 0 12) : "
    read -r minute hour
    if [[ $minute == 0 ]] && [[ $hour == 0 ]]; then
        cron_time="* * * * *"
        break
    elif [[ $minute == 0 ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]]; then
        cron_time="0 */${hour} * * *"
        break
    elif [[ $hour == 0 ]] && [[ $minute =~ ^[0-9]+$ ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} * * * *"
        break
    elif [[ $minute =~ ^[0-9]+$ ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} */${hour} * * *"
        break
    else
        echo "Invalid input, please enter a valid cronjob format (minutes and hours, e.g: 0 6 or 30 12)"
    fi
done

# Marzban backup
# Removed the choice logic, "$xmh" is always "m"
if true; then

# Check if the Marzban directory exists
if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
  echo "The folder exists at $dir"
else
  echo "The folder does not exist."
  exit 1
fi

# Backup logic for Docker MySQL
MYSQL_CONTAINER_NAME="marzban-mysql-1"  # Ensure this matches the name of your MySQL container

# Backup MySQL data from the Docker volume
BACKUP_DIR="/root/mysql-backup"
docker exec $MYSQL_CONTAINER_NAME bash -c "mkdir -p /var/lib/mysql/db-backup"
docker exec $MYSQL_CONTAINER_NAME bash -c "mysqldump -u root -p\$MYSQL_ROOT_PASSWORD --all-databases > /var/lib/mysql/db-backup/all_databases.sql"

# Create a backup ZIP of the Marzban data and MySQL
ZIP=$(cat <<EOF
docker exec $MYSQL_CONTAINER_NAME bash -c "tar czf /var/lib/mysql/db-backup/mysql-data.tar.gz -C /var/lib/docker/volumes/mysql/_data ."
docker cp $MYSQL_CONTAINER_NAME:/var/lib/mysql/db-backup/mysql-data.tar.gz /root/
zip -r /root/ac-backup-m.zip ${dir}/* /var/lib/marzban/* /opt/marzban/.env /root/mysql-backup/*
rm -rf /root/mysql-backup/*
rm -rf /var/lib/mysql/db-backup/*
EOF
)

ACLover="marzban backup"

else
echo "Please choose m only !"
exit 1
fi

trim() {
    # remove leading and trailing whitespace/lines
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
caption="${caption}\n\n${ACLover}\n<code>${IP}</code>\n"
comment=$(echo -e "$caption" | sed 's/<code>//g;s/<\/code>//g')
comment=$(trim "$comment")

# install zip
sudo apt install zip -y

# send backup to telegram
cat > "/root/ac-backup-${xmh}.sh" <<EOL
rm -rf /root/ac-backup-${xmh}.zip
$ZIP
echo -e "$comment" | zip -z /root/ac-backup-${xmh}.zip
curl -F chat_id="${chatid}" -F caption=\$'${caption}' -F parse_mode="HTML" -F document=@"/root/ac-backup-${xmh}.zip" https://api.telegram.org/bot${tk}/sendDocument
EOL

# Add cronjob
{ crontab -l -u root; echo "${cron_time} /bin/bash /root/ac-backup-${xmh}.sh >/dev/null 2>&1"; } | crontab -u root -

# run the script
bash "/root/ac-backup-${xmh}.sh"

# Done
echo -e "\nDone\n"
