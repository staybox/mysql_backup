#!/bin/bash

# Переменные
VG_NAME="my_vg"            # Имя группы томов
LV_NAME="mysql_lv"          # Имя логического тома
SNAP_NAME="mysql_snapshot"  # Имя снепшота
SNAP_SIZE="1G"              # Размер снепшота
MOUNT_POINT="/mnt/mysql_snapshot" # Точка монтирования для снепшота
BACKUP_DIR="/var/backups/mysql"   # Папка для бэкапов
DATE=$(date +"%Y-%m-%d_%H-%M-%S") # Текущая дата и время
BACKUP_FILE="$BACKUP_DIR/mysql_backup_$DATE.tar.gz" # Имя файла бэкапа

# 1. Убедитесь, что папка для бэкапов существует
mkdir -p $BACKUP_DIR

# 2. Остановка записи в MySQL
echo "Замораживание базы данных MySQL..."
mysql -u root -p -e "FLUSH TABLES WITH READ LOCK;" # Заморозить записи
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось заморозить записи в MySQL."
    exit 1
fi

# 3. Ставим MySQL в безопасный режим для бэкапа (полная синхронизация)
mysql -u root -p -e "SET GLOBAL innodb_fast_shutdown = 0;"

# 4. Создаем LVM снепшот
echo "Создание LVM снепшота..."
lvcreate --size $SNAP_SIZE --snapshot --name $SNAP_NAME /dev/$VG_NAME/$LV_NAME
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось создать LVM снепшот."
    mysql -u root -p -e "UNLOCK TABLES;" # Снятие блокировки
    exit 1
fi

# 5. Разблокировка MySQL и возврат innodb_fast_shutdown в режим 1
mysql -u root -p -e "UNLOCK TABLES;"
mysql -u root -p -e "SET GLOBAL innodb_fast_shutdown = 1;"
echo "Записи в MySQL разрешены, innodb_fast_shutdown восстановлен."

# 6. Монтирование снепшота
echo "Монтирование снепшота..."
mkdir -p $MOUNT_POINT
mount /dev/$VG_NAME/$SNAP_NAME $MOUNT_POINT
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось смонтировать LVM снепшот."
    lvremove -f /dev/$VG_NAME/$SNAP_NAME
    exit 1
fi

# 7. Создание бэкапа
echo "Создание архива базы данных..."
tar -czvf $BACKUP_FILE -C $MOUNT_POINT .
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось создать архив базы данных."
    umount $MOUNT_POINT
    lvremove -f /dev/$VG_NAME/$SNAP_NAME
    exit 1
fi

# 8. Отмонтирование снепшота и его удаление
echo "Отмонтирование и удаление снепшота..."
umount $MOUNT_POINT
lvremove -f /dev/$VG_NAME/$SNAP_NAME

# 9. Уведомление о завершении
echo "Бэкап завершен. Файл бэкапа: $BACKUP_FILE"
