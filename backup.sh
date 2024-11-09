#!/bin/bash

# Получение токена бота от пользователя
while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
    if [[ $tk == $'\0' ]]; then
        echo "Invalid input. Token cannot be empty."
        unset tk
    fi
done

# Получение chat ID
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

# Заголовок для резервной копии
echo "Caption (for example, your domain, to identify the backup more easily): "
read -r caption

# Настройка cronjob для регулярного выполнения
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

# Пути к директориям для резервного копирования
directories_to_backup=(
    "/opt/marzban"
    "/var/lib/marzban"
    "/opt/marzban/.env"
)

# Путь к данным MySQL в Docker
mysql_data_path="/var/lib/docker/volumes/mysql/_data"

# Проверка наличия директории с данными MySQL
if [ -d "$mysql_data_path" ]; then
    echo "MySQL data directory found at $mysql_data_path"
    
    # Создаем резервную копию всех данных MySQL через mysqldump внутри контейнера
    docker exec -t mysql-container-name mysqldump -u root -pYOUR_PASSWORD --all-databases > /root/mysql_backup.sql

    # Архивируем директорию с данными MySQL
    backup_filename="/root/mysql_backup_$(date +'%Y%m%d_%H%M%S').tar.gz"
    tar -czf "$backup_filename" -C "$mysql_data_path" .

    # Добавляем другие директории в архив
    backup_filename_all="/root/marzban_backup_$(date +'%Y%m%d_%H%M%S').tar.gz"
    tar -czf "$backup_filename_all" "${directories_to_backup[@]}" /root/mysql_backup.sql

    # Отправка архивного файла в Telegram
    curl -X POST "https://api.telegram.org/bot$tk/sendDocument" \
        -F chat_id=$chatid \
        -F document=@"$backup_filename_all" \
        -F caption="$caption"

    # Сохранение архива в локальном каталоге для дальнейших копий
    local_backup_path="/home/backups/marzban_backup_$(date +'%Y%m%d_%H%M%S').tar.gz"
    cp "$backup_filename_all" "$local_backup_path"

    # Опционально: Удаление старых архивов (например, более 30 дней)
    find /home/backups/ -type f -name "marzban_backup_*.tar.gz" -mtime +30 -exec rm {} \;

    # Уведомление о завершении
    echo "Backup completed and sent to Telegram. Local backup saved at $local_backup_path."
else
    echo "MySQL data directory not found at $mysql_data_path!"
    exit 1
fi
