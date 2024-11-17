#!/bin/sh

set -x

get_wireguard_interfaces() {
    echo "Запускаем функцию get_wireguard_interfaces" >&2
    echo "Вывод команды 'ip a':" >&2
    ip a >&2

    # Извлечение WireGuard интерфейсов
    interfaces=$(ip a | grep -oP '^(\d+):\s+\K(nwg[^\s:]+)')
    echo "Найденные интерфейсы WireGuard:" >&2
    echo "$interfaces" >&2

    # Проверка наличия интерфейсов
    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов." >&2
        exit 1
    fi

    echo "$interfaces"
}

select_wireguard_interface() {
    echo "Запускаем функцию select_wireguard_interface" >&2
    interfaces=$(get_wireguard_interfaces)

    echo "Результат функции get_wireguard_interfaces:" >&2
    echo "$interfaces" >&2

    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов." >&2
        exit 1
    fi

    echo "Формируем список для выбора:" >&2

    # Нумерация строк с помощью awk
    echo "$interfaces" | awk '{print NR ". " $0}'

    # Считывание выбора пользователя
    read -p "Ваш выбор (номер): " choice

    # Выбор интерфейса
    selected=$(echo "$interfaces" | awk "NR==$choice")
    echo "Выбранный интерфейс: $selected" >&2

    # Проверка на пустой выбор
    if [ -z "$selected" ]; then
        echo "Неверный выбор. Завершаем выполнение скрипта." >&2
        exit 1
    fi

    echo "$selected"
}

echo "Запускаем основную часть скрипта" >&2

# Получение и проверка выбранного интерфейса
WG_INTERFACE=$(select_wireguard_interface)
echo "Результат выбора интерфейса: $WG_INTERFACE" >&2

if [ -z "$WG_INTERFACE" ]; then
    echo "Ошибка: не удалось определить интерфейс WireGuard." >&2
    exit 1
fi

echo "Выбран интерфейс WireGuard: $WG_INTERFACE"
