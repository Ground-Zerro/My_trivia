#!/bin/sh

# Включаем режим отладки
set -x

# Функция для получения списка интерфейсов WireGuard
get_wireguard_interfaces() {
    echo "Запускаем функцию get_wireguard_interfaces" >&2
    echo "Вывод команды 'ip a':" >&2
    ip a >&2  # Отображаем полный вывод команды для отладки

    # Получаем список интерфейсов WireGuard
    interfaces=$(ip a | grep -oP '^(\d+):\s+\K(nwg[^\s:]+)')

    echo "Найденные интерфейсы WireGuard:" >&2
    echo "$interfaces" >&2

    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов." >&2
        exit 1  # Завершаем выполнение всего скрипта при ошибке
    fi

    echo "$interfaces"
}

# Функция выбора интерфейса WireGuard
select_wireguard_interface() {
    echo "Запускаем функцию select_wireguard_interface" >&2
    interfaces=$(get_wireguard_interfaces)

    echo "Результат функции get_wireguard_interfaces:" >&2
    echo "$interfaces" >&2

    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов." >&2
        exit 1  # Завершаем выполнение всего скрипта при ошибке
    fi

    echo "Формируем список для выбора:" >&2
    echo "$interfaces" | nl -w1 -s'. ' >&2  # Показываем список для выбора

    read -p "Ваш выбор: " choice
    echo "Пользователь выбрал: $choice" >&2

    selected=$(echo "$interfaces" | sed -n "${choice}p")
    echo "Выбранный интерфейс: $selected" >&2

    if [ -z "$selected" ]; then
        echo "Неверный выбор. Завершаем выполнение скрипта." >&2
        exit 1  # Завершаем выполнение всего скрипта при ошибке
    fi

    echo "$selected"
}

# Основная часть скрипта
echo "Запускаем основную часть скрипта" >&2

# Получение интерфейса WireGuard
WG_INTERFACE=$(select_wireguard_interface)
echo "Результат выбора интерфейса: $WG_INTERFACE" >&2

if [ -z "$WG_INTERFACE" ]; then
    echo "Ошибка: не удалось определить интерфейс WireGuard." >&2
    exit 1  # Завершаем выполнение всего скрипта при ошибке
fi

echo "Выбран интерфейс WireGuard: $WG_INTERFACE"
