#!/bin/sh

SCRIPT="work.sh"
TMP_DIR="/tmp"

# Удаляем старую версию скрипта, если она существует
rm -f "$TMP_DIR/$SCRIPT"

# Скачиваем новый скрипт
curl -sL "https://raw.githubusercontent.com/Ground-Zerro/My_trivia/refs/heads/main/$SCRIPT" --output "$TMP_DIR/$SCRIPT"

# Назначаем права на выполнение
chmod +x "$TMP_DIR/$SCRIPT"

# Выполняем скрипт в интерактивном режиме
"$TMP_DIR/$SCRIPT"
