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

    # Преобразование интерфейсов в нумерованный список
    IFS=$'\n' read -r -d '' -a interface_array <<< "$(echo "$interfaces")"

    for i in "${!interface_array[@]}"; do
        echo "$((i + 1)). ${interface_array[$i]}"
    done

    # Считывание выбора пользователя
    read -p "Ваш выбор (номер): " choice

    # Проверка, что выбор корректен
    if ! [ "$choice" -ge 1 ] 2>/dev/null || [ "$choice" -gt "${#interface_array[@]}" ]; then
        echo "Неверный выбор. Завершаем выполнение скрипта." >&2
        exit 1
    fi

    # Определение выбранного интерфейса
    selected="${interface_array[$((choice - 1))]}"
    echo "Выбранный интерфейс: $selected" >&2

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
