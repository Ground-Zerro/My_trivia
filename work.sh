#!/bin/sh

# Получаем список интерфейсов с ip a, фильтруем только интерфейсы, начинающиеся с 'nwg'
interfaces=$(ip a | grep -oP '^\d+: (\S+):' | grep 'nwg' | sed 's/://')

# Проверяем, есть ли такие интерфейсы
if [ -z "$interfaces" ]; then
    echo "Не найдено доступных интерфейсов WireGuard."
    exit 1
fi

# Выводим список интерфейсов для выбора
echo "Выберите интерфейс:"
i=1
for iface in $interfaces; do
    # Получаем IP-адрес интерфейса, используя ip a show
    ip_address=$(ip a show "$iface" | grep -oP 'inet \K[\d.]+')

    # Если IP-адрес найден, выводим интерфейс и его IP
    if [ -n "$ip_address" ]; then
        echo "$i. $iface: $ip_address"
        i=$((i+1))
    fi
done

# Запрашиваем выбор пользователя
read -p "Введите номер интерфейса: " choice

# Присваиваем выбранный интерфейс переменной, извлекая только имя интерфейса без лишних символов
net_interface=$(echo "$interfaces" | sed -n "${choice}p")

# Если в переменной net_interface есть лишний номер, убираем его
net_interface=$(echo "$net_interface" | sed 's/^[0-9]*: //')

# Выводим выбранный интерфейс
echo "Выбран интерфейс: $net_interface"

# Удаляем скрипт после выполнения
rm -- "$0"
