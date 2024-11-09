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

# Get the server IP
server_ip=$(hostname -I | awk '{print $1}')
echo "Server IP: $server_ip"

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

# x-ui or marzban or hiddify
while [[ -z "$xmh" ]]; do
    echo "x-ui or marzban or hiddify? [x/m/h] : "
    read -r xmh
    if [[ $xmh == $'\0' ]]; then
        echo "Invalid input. Please choose x, m or h."
        unset xmh
    elif [[ ! $xmh =~ ^[xmh]$ ]]; then
        echo "${xmh} is not a valid option. Please choose x, m or h."
        unset xmh
    fi
done

# m backup
if [[ "$xmh" == "m" ]]; then

if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
  echo "The folder exists at $dir"
else
  echo "The folder does not exist."
  exit 1
fi

if [ -d "/var/lib/marzban/mysql" ]; then

  sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /opt/marzban/.env

  docker exec marzban-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"
  source /opt/marzban/.env

  # Check if MySQL is running in Docker
  if docker ps | grep -q 'mysql'; then
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        echo "Please provide the MySQL root password: "
        read -r MYSQL_ROOT_PASSWORD
    fi
    PASSWORD="$MYSQL_ROOT_PASSWORD"
  else
    PASSWORD="$MYSQL_PASSWORD"
  fi

  cat > "/var/lib/marzban/mysql/ac-backup.sh" <<EOL
#!/bin/bash

USER="root"
PASSWORD="$PASSWORD"

# Make SQL dump of databases
databases=\$(mysql -h 127.0.0.1 --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)

for db in \$databases; do
    if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]] ; then
        echo "Dumping database: \$db"
        mysqldump -h 127.0.0.1 --user=\$USER --password=\$PASSWORD \$db > /var/lib/mysql/db-backup/\$db.sql
    fi
done
EOL
chmod +x /var/lib/marzban/mysql/ac-backup.sh

ZIP="docker exec marzban-mysql-1 bash -c '/var/lib/marzban/mysql/ac-backup.sh'; zip -r /root/ac-backup-m.zip /opt/marzban/* /var/lib/marzban/* /opt/marzban/.env -x /var/lib/marzban/mysql/*"

# Send backup to Telegram without "Backup complete" message
echo "Starting backup of $caption ..."
eval $ZIP

BACKUP_FILE_PATH=$(find /root -iname "*.zip" -print -quit)

SEND_FILE=$(curl -s -X POST \
    -F "chat_id=$chatid" \
    -F "document=@$BACKUP_FILE_PATH" \
    -F "caption=$caption-backup.zip (Server IP: $server_ip)" \
    "https://api.telegram.org/bot$tk/sendDocument")

if [[ -f "$BACKUP_FILE_PATH" ]]; then
    rm -rf "$BACKUP_FILE_PATH"
fi

else
  echo "The MySQL directory does not exist."
  exit 1
fi

fi

# Add cron job
if [[ ! -z "$cron_time" ]]; then
    (crontab -l 2>/dev/null; echo "$cron_time /root/backup.sh") | crontab -
    echo "Cron job added successfully."
fi
