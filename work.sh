#!/bin/sh

# Получаем список интерфейсов с ip a, фильтруем только интерфейсы, начинающиеся с 'nwg'
interfaces=$(ip a | grep -oP '^(\d+: )?nwg[0-9]+' | sed 's/^[ \t]*//')

# Проверяем, есть ли такие интерфейсы
if [ -z "$interfaces" ]; then
    echo "Не найдено доступных интерфейсов WireGuard."
    exit 1
fi

# Выводим список интерфейсов для выбора
echo "Выберите интерфейс:"
i=1
for iface in $interfaces; do
    ip_address=$(ip a show $iface | grep -oP 'inet \K[\d.]+')
    echo "$i. $iface: $ip_address"
    i=$((i+1))
done

# Запрашиваем выбор пользователя
read -p "Введите номер интерфейса: " choice

# Присваиваем выбранный интерфейс переменной
net_interface=$(echo "$interfaces" | sed -n "${choice}p")

# Выводим выбранный интерфейс
echo "Выбран интерфейс: $net_interface"

# Удаляем скрипт после выполнения
rm -- "$0"
