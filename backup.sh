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

# MySQL root password
while [[ -z "$MYSQL_ROOT_PASSWORD" ]]; do
    echo "MySQL root password: "
    read -r -s MYSQL_ROOT_PASSWORD
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        echo "Invalid input. Password cannot be empty."
    fi
done

# Save MySQL root password for future runs
echo "$MYSQL_ROOT_PASSWORD" > /root/.mysql_password

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

# Marzban backup (since $xmh is always "m")
if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
  echo "The folder exists at $dir"
else
  echo "The folder does not exist."
  exit 1
fi

# MySQL backup in Docker
if [ -d "/var/lib/docker/volumes/mysql/_data" ]; then

  echo "Starting Marzban backup..."

  # Backup script for MySQL database in Docker
  cat > "/root/ac-backup-m.sh" <<EOL
#!/bin/bash

MYSQL_ROOT_PASSWORD=$(cat /root/.mysql_password)
BACKUP_DIR="/root/marzban-backup"
mkdir -p \$BACKUP_DIR

# Backup MySQL database inside Docker container
docker exec marzban-mysql-container bash -c "mysqldump -u root --password=\$MYSQL_ROOT_PASSWORD --all-databases > /tmp/all-databases.sql"
docker cp marzban-mysql-container:/tmp/all-databases.sql \$BACKUP_DIR/all-databases.sql

# Zip the backup
zip -r /root/ac-backup-m.zip \$BACKUP_DIR/* /opt/marzban/* /var/lib/marzban/* /opt/marzban/.env
rm -rf \$BACKUP_DIR

EOL
chmod +x /root/ac-backup-m.sh

# Set caption with the IP address and comment
IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
caption="${caption}\n\nMarzban backup\n<code>${IP}</code>\n"
comment=$(echo -e "$caption" | sed 's/<code>//g;s/<\/code>//g')

# Install zip
sudo apt install zip -y

# Send backup to Telegram
cat > "/root/ac-backup-send-to-telegram.sh" <<EOL
rm -rf /root/ac-backup-${xmh}.zip
/root/ac-backup-m.sh
echo -e "$comment" | zip -z /root/ac-backup-m.zip
curl -F chat_id="${chatid}" -F caption=\$'${caption}' -F parse_mode="HTML" -F document=@"/root/ac-backup-m.zip" https://api.telegram.org/bot${tk}/sendDocument
EOL

# Add cronjob
{ crontab -l -u root; echo "${cron_time} /bin/bash /root/ac-backup-send-to-telegram.sh >/dev/null 2>&1"; } | crontab -u root -

# Run the script
bash "/root/ac-backup-send-to-telegram.sh"

# Done
echo -e "\nDone\n"
EOL

# Done
echo "Backup script setup complete."
