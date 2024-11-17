#!/bin/sh

# Выводим список интерфейсов для выбора
echo "Доступные интерфейсы:"
i=1
interfaces=$(ip a | sed -n 's/.*: \(.*\): <.*UP.*/\1/p')  # Список интерфейсов
interface_list=""  # Строка для хранения интерфейсов
for iface in $interfaces; do
    # Проверяем, существует ли интерфейс, игнорируя ошибки 'ip: can't find device'
    if ip a show "$iface" &>/dev/null; then
        # Получаем IP-адрес интерфейса, используя ip a show
        ip_address=$(ip a show "$iface" | grep -oP 'inet \K[\d.]+')

        # Если IP-адрес найден, выводим интерфейс и его IP
        if [ -n "$ip_address" ]; then
            echo "$i. $iface: $ip_address"
            interface_list="$interface_list $iface"  # Добавляем интерфейс в строку
            i=$((i+1))
        fi
    fi
done

# Запрашиваем у пользователя имя интерфейса с проверкой ввода
while true; do
    read -p "Введите ИМЯ интерфейса: " net_interface

    # Проверяем, существует ли введенное имя в списке интерфейсов
    if echo "$interface_list" | grep -qw "$net_interface"; then
        # Если интерфейс найден, завершаем цикл
        echo "Выбран интерфейс: $net_interface"
        break
    else
        # Если введен неверный интерфейс, выводим сообщение об ошибке
        echo "Неверный выбор, необходимо ввести ИМЯ интерфейса из списка."
    fi
done

# Удаляем скрипт после выполнения
rm -- "$0"

#control