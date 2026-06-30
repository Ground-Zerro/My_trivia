#!/bin/bash

# Обновление системы
sudo apt update
sudo apt upgrade -y

# Добавляем модули ядра (BBR + conntrack для nf_conntrack_max)
sudo sed -i '/tcp_bbr/d' /etc/modules-load.d/modules.conf
sudo sed -i '/nf_conntrack/d' /etc/modules-load.d/modules.conf
{
    echo "tcp_bbr"
    echo "nf_conntrack"
} | sudo tee -a /etc/modules-load.d/modules.conf > /dev/null

# Загружаем модули сразу, чтобы sysctl не ругался
sudo modprobe tcp_bbr 2>/dev/null
sudo modprobe nf_conntrack 2>/dev/null

# Функция удаления существующих записей из sysctl.conf
remove_existing() {
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # Экранируем точки для sed и удаляем строку вида "param = value" / "param=value"
        escaped=$(printf '%s' "$line" | sed 's/\./\\./g')
        sudo sed -i "\|^[[:space:]]*${escaped}[[:space:]]*=|d" /etc/sysctl.conf
    done
}

# Удаление существующих записей из /etc/sysctl.conf
cat <<EOF | remove_existing
fs.file-max
fs.inotify.max_user_instances
net.core.default_qdisc
net.core.netdev_max_backlog
net.core.rmem_max
net.core.somaxconn
net.core.wmem_default
net.core.wmem_max
net.ipv4.ip_local_port_range
net.ipv4.tcp_congestion_control
net.ipv4.tcp_fastopen
net.ipv4.tcp_fin_timeout
net.ipv4.tcp_keepalive_intvl
net.ipv4.tcp_keepalive_probes
net.ipv4.tcp_keepalive_time
net.ipv4.tcp_max_syn_backlog
net.ipv4.tcp_max_tw_buckets
net.ipv4.tcp_mem
net.ipv4.tcp_mtu_probing
net.ipv4.tcp_rmem
net.ipv4.tcp_slow_start_after_idle
net.ipv4.tcp_syncookies
net.ipv4.tcp_tw_reuse
net.ipv4.tcp_wmem
net.ipv4.udp_mem
net.ipv6.conf.all.max_addresses
net.ipv6.conf.default.max_addresses
net.ipv6.route.max_size
net.netfilter.nf_conntrack_max
EOF

# Добавляем новые параметры
cat <<EOF | sudo tee -a /etc/sysctl.conf > /dev/null
fs.file-max=2097152
fs.inotify.max_user_instances=8192
net.core.default_qdisc=fq
net.core.netdev_max_backlog=65535
net.core.rmem_max=16777216
net.core.somaxconn=65535
net.core.wmem_default=2097152
net.core.wmem_max=16777216
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_mem=786432 1048576 1572864
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.udp_mem=786432 1048576 1572864
net.ipv6.conf.all.max_addresses=16
net.ipv6.conf.default.max_addresses=16
net.ipv6.route.max_size=2147483647
net.netfilter.nf_conntrack_max=2097152
EOF

# Применяем настройки
sudo sysctl -p

# Swap: создаём только если /swapfile не существует и не подключён
if swapon --show | grep -q '/swapfile' || [ -f /swapfile ]; then
    echo "Swap уже существует, пропускаем создание."
else
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "Swap создан и активирован."
fi

# Прописываем swap в fstab только если там ещё нет записи
if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
fi

swapon --show

# Обратный отсчёт и ребут
for ((i=10; i>=0; i--)); do
    if [ $i -eq 10 ]; then
        echo -ne "Сервер будет перезагружен через: $i\r"
    elif [ $i -eq 0 ]; then
        echo -ne "Сервер будет перезагружен через: $i\n"
    else
        echo -ne "Сервер будет перезагружен через: $i \r"
    fi
    sleep 1
done

# Удаление скрипта и перезагрузка
rm -- "$0"
sudo reboot
