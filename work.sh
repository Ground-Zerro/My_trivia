#!/bin/sh

# Получаем список интерфейсов с ip a, фильтруем по типам интерфейсов для VPN
interfaces=$(ip a | grep -E "nwg" | awk -F: '{print $2}' | sed 's/^[ \t]*//')

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
