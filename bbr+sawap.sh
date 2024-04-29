#!/bin/bash

# Обновление системы
apt update
apt upgrade -y

# Добавляем модуль BBR
sed -i '/.*tcp_bbr.*/d' /etc/modules-load.d/modules.conf
echo "tcp_bbr" >> /etc/modules-load.d/modules.conf

# Функция удаления существующих записей
remove_existing() {
    while read -r line; do
        sed -i "/$line/d" /etc/sysctl.conf
    done
}

# Удаление существующих записей из файла /etc/sysctl.conf
cat <<EOF | remove_existing
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
EOF

# Добавляем новые параметры в файл sysctl.conf
cat <<EOF >> /etc/sysctl.conf
fs.inotify.max_user_instances=8192
net.core.default_qdisc=fq
net.core.netdev_max_backlog=10240
net.core.rmem_max=67108864
net.core.somaxconn=8192
net.core.wmem_default=2097152
net.core.wmem_max=67108864
net.ipv4.ip_local_port_range=1024 45000
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_keepalive_time=1200
net.ipv4.tcp_max_syn_backlog=10240
net.ipv4.tcp_max_tw_buckets=5000
net.ipv4.tcp_mem=25600 51200 102400
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_rmem=16384 262144 8388608
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_wmem=32768 524288 16777216
net.ipv4.udp_mem=25600 51200 102400
EOF

# Применяем настройки
sysctl -p

# Свап файл на 2 Ггб
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
swapon --show

# Обратный отсчет и ребут
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
reboot
