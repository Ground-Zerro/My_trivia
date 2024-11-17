#!/bin/sh

SCRIPT="work.sh"
TMP_DIR="/tmp"

# Удаляем файл, если он существует
rm -f "$TMP_DIR/$SCRIPT"

# Скачиваем новый файл
curl -L -s "https://raw.githubusercontent.com/Ground-Zerro/My_trivia/refs/heads/main/$SCRIPT" --output "$TMP_DIR/$SCRIPT"

# Назначаем права на выполнение
chmod +x "$TMP_DIR/$SCRIPT"

# Выполняем скрипт
"$TMP_DIR/$SCRIPT"
