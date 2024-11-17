#!/bin/sh

get_wireguard_interfaces() {
    # Извлечение интерфейсов WireGuard
    interfaces=$(ip a | grep -oP '^(\d+):\s+\K(nwg[^\s:]+)')
    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов."
        exit 1
    fi
    echo "$interfaces"
}

select_wireguard_interface() {
    interfaces=$(get_wireguard_interfaces)

    # Преобразование интерфейсов в массив
    IFS=$'\n' read -r -d '' -a interface_array <<< "$(echo "$interfaces")"

    # Отображение списка интерфейсов
    echo "Выберите интерфейс WireGuard:"
    for i in "${!interface_array[@]}"; do
        echo "$((i + 1)). ${interface_array[$i]}"
    done

    # Считывание выбора пользователя
    while true; do
        read -p "Ваш выбор (номер): " choice
        # Проверка, что выбор является числом и в пределах диапазона
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#interface_array[@]}" ]; then
            # Возвращаем выбранный интерфейс
            echo "${interface_array[$((choice - 1))]}"
            break
        else
            echo "Неверный выбор. Пожалуйста, выберите номер из списка."
        fi
    done
}

# Основной блок
WG_INTERFACE=$(select_wireguard_interface)

if [ -z "$WG_INTERFACE" ]; then
    echo "Ошибка: не удалось определить интерфейс WireGuard."
    exit 1
fi

echo "Выбран интерфейс WireGuard: $WG_INTERFACE"
