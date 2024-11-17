#!/bin/sh

# Функция для получения списка интерфейсов WireGuard
get_wireguard_interfaces() {
    # Получаем список интерфейсов WireGuard
    interfaces=$(ip a | sed -n 's/.*nwg\(.*\): <.*UP.*/nwg\1/p')

    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов."
        exit 1  # Завершаем выполнение всего скрипта при ошибке
    fi

    echo "Найдено $(echo "$interfaces" | wc -w) интерфейсов WireGuard."
    for iface in $interfaces; do
        echo "$iface"
    done
}

# Функция выбора интерфейса WireGuard
select_wireguard_interface() {
    echo "Поиск доступных WireGuard интерфейсов..."
    interfaces=$(get_wireguard_interfaces)

    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов."
        exit 1  # Завершаем выполнение всего скрипта при ошибке
    fi

    echo "Найдено $(echo "$interfaces" | wc -l) интерфейсов WireGuard."
    echo "Введите номер интерфейса для использования:"

    # Формируем список для выбора
    echo "$interfaces" | awk '{printf "%d. %s\n", NR, $1}'

    read -p "Ваш выбор: " choice
    selected=$(echo "$interfaces" | awk -v num="$choice" 'NR == num {print $1}')

    if [ -z "$selected" ]; then
        echo "Неверный выбор. Завершаем выполнение скрипта."
        exit 1  # Завершаем выполнение всего скрипта при ошибке
    fi

    echo "$selected"
}

# Основная часть скрипта

# Получение интерфейса WireGuard
WG_INTERFACE=$(select_wireguard_interface)
if [ -z "$WG_INTERFACE" ]; then
    echo "Ошибка: не удалось определить интерфейс WireGuard."
    exit 1  # Завершаем выполнение всего скрипта при ошибке
fi

echo "Выбран интерфейс WireGuard: $WG_INTERFACE"
