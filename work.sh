#!/bin/sh

# Функция для получения списка интерфейсов WireGuard
get_wireguard_interfaces() {
    # Получаем список интерфейсов WireGuard
    interfaces=$(ip a | grep -oP '^(\d+):\s+\K(nwg[^\s:]+)')

    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов."
        exit 1  # Завершаем выполнение всего скрипта при ошибке
    fi

    echo "Найдено $(echo "$interfaces" | wc -l) интерфейсов WireGuard."
    echo "$interfaces"
}

# Функция выбора интерфейса WireGuard
select_wireguard_interface() {
    echo "Поиск доступных WireGuard интерфейсов..."
    interfaces=$(get_wireguard_interfaces)

    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов."
        exit 1  # Завершаем выполнение всего скрипта при ошибке
    fi

    echo "Выберите интерфейс для использования:"
    echo "$interfaces" | nl -w1 -s'. '

    read -p "Ваш выбор: " choice
    selected=$(echo "$interfaces" | sed -n "${choice}p")

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
