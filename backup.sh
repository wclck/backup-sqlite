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

while [[ -z "$crontabs" ]]; do
    echo "Would you like the previous crontabs to be cleared? [y/n] : "
    read -r crontabs
    if [[ $crontabs == $'\0' ]]; then
        echo "Invalid input. Please choose y or n."
        unset crontabs
    elif [[ ! $crontabs =~ ^[yn]$ ]]; then
        echo "${crontabs} is not a valid option. Please choose y or n."
        unset crontabs
    fi
done

if [[ "$crontabs" == "y" ]]; then
    sudo crontab -l | grep -vE '/root/ac-backup.+\.sh' | crontab -
fi

# m backup
if [[ "$xmh" == "m" ]]; then

    # Checking for Marzban directory
    if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
      echo "The folder exists at $dir"
    else
      echo "The folder does not exist."
      exit 1
    fi

    # Checking if MySQL is running in Docker or locally
    if docker ps --format '{{.Names}}' | grep -q "mysql"; then
        # Docker MySQL backup
        docker exec mysql bash -c "mkdir -p /var/lib/mysql/db-backup"
        ZIP=$(cat <<EOF
docker exec mysql bash -c "mysqldump -u root -p${MYSQL_ROOT_PASSWORD} marzban > /var/lib/mysql/db-backup/marzban.sql"
zip -r /root/ac-backup-m.zip ${dir}/* /var/lib/marzban/* /opt/marzban/.env -x /var/lib/marzban/mysql/\*
zip -r /root/ac-backup-m.zip /var/lib/mysql/db-backup/*
rm -rf /var/lib/mysql/db-backup/*
EOF
)
    elif [ -d "/var/lib/marzban/mysql" ]; then
        # Local MySQL backup
        sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /opt/marzban/.env
        source /opt/marzban/.env

        cat > "/var/lib/marzban/mysql/ac-backup.sh" <<EOL
#!/bin/bash
USER="root"
PASSWORD="$MYSQL_ROOT_PASSWORD"

databases=\$(mysql -h 127.0.0.1 --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)

for db in \$databases; do
    if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]] ; then
        echo "Dumping database: \$db"
        mysqldump -h 127.0.0.1 --force --opt --user=\$USER --password=\$PASSWORD --databases \$db > /var/lib/mysql/db-backup/\$db.sql
    fi
done
EOL
        chmod +x /var/lib/marzban/mysql/ac-backup.sh

        ZIP=$(cat <<EOF
bash /var/lib/marzban/mysql/ac-backup.sh
zip -r /root/ac-backup-m.zip /opt/marzban/* /var/lib/marzban/* /opt/marzban/.env -x /var/lib/marzban/mysql/\*
zip -r /root/ac-backup-m.zip /var/lib/marzban/mysql/db-backup/*
rm -rf /var/lib/marzban/mysql/db-backup/*
EOF
)
    else
        ZIP="zip -r /root/ac-backup-m.zip ${dir}/* /var/lib/marzban/* /opt/marzban/.env"
    fi

    ACLover="marzban backup"
    
# x-ui backup
elif [[ "$xmh" == "x" ]]; then
    if dbDir=$(find /etc /opt/freedom -type d -iname "x-ui*" -print -quit); then
      echo "The folder exists at $dbDir"
      if [[ $dbDir == *"/opt/freedom/x-ui"* ]]; then
         dbDir="${dbDir}/db/"
      fi
    else
      echo "The folder does not exist."
      exit 1
    fi

    if configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit); then
      echo "The folder exists at $configDir"
    else
      echo "The folder does not exist."
      exit 1
    fi

    ZIP="zip /root/ac-backup-x.zip ${dbDir}/x-ui.db ${configDir}/config.json"
    ACLover="x-ui backup"

# hiddify backup
elif [[ "$xmh" == "h" ]]; then
    if ! find /opt/hiddify-manager/hiddify-panel/ -type d -iname "backup" -print -quit; then
      echo "The folder does not exist."
      exit 1
    fi

    ZIP=$(cat <<EOF
cd /opt/hiddify-manager/hiddify-panel/
if [ $(find /opt/hiddify-manager/hiddify-panel/backup -type f | wc -l) -gt 100 ]; then
  find /opt/hiddify-manager/hiddify-panel/backup -type f -delete
fi
python3 -m hiddifypanel backup
cd /opt/hiddify-manager/hiddify-panel/backup
latest_file=\$(ls -t *.json | head -n1)
rm -f /root/ac-backup-h.zip
zip /root/ac-backup-h.zip /opt/hiddify-manager/hiddify-panel/backup/\$latest_file
EOF
)
    ACLover="hiddify backup"
else
    echo "Please choose m or x or h only!"
    exit 1
fi

# Additional configuration

# Install zip
sudo apt install zip -y

# Send backup to Telegram
cat > "/root/ac-backup-${xmh}.sh" <<EOL
rm -rf /root/ac-backup-${xmh}.zip
$ZIP
echo -e "$comment" | zip -z /root
