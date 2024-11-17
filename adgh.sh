#!/bin/sh

# Функция для получения списка интерфейсов
get_interfaces() {
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
}

# Функция отключения системного DNS-сервера роутера
rci_post() {
    $WGET -qO - --post-data="$1" localhost:79/rci/ > /dev/null 2>&1
}

# Основная часть скрипта
get_interfaces  # Вызов функции для получения интерфейса

echo "Установка необходимых пакетов..."
opkg update
opkg install adguardhome-go ipset iptables ip-full

# Добавляем ipset в AdGuard Home
echo "Настройка AdGuard Home..."
sed -i 's|ipset_file: .*|ipset_file: /opt/etc/AdGuardHome/ipset.conf|' /opt/etc/AdGuardHome/AdGuardHome.yaml

# Инициализация WGET
WGET='/opt/bin/wget -q --no-check-certificate'

# Выполняем команду отключения DNS провайдера
curl -s "http://localhost:79/rci/opkg/dns-override" | grep -q true || {
    echo 'Отключаем работу через DNS-провайдера роутера...'
    echo "Возможно, что сейчас произойдет выход из сессии..."
    echo "В этом случае необходимо заново войти в сессию по ssh и запустить скрипт"
    rci_post '[{"opkg": {"dns-override": true}},{"system": {"configuration": {"save": true}}}]' &>/dev/null
}

# Создание скрипта для ipset
echo "Создание скрипта для ipset..."
cat << EOF > /opt/etc/init.d/S52ipset
#!/bin/sh

PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ "\$1" = "start" ]; then
    ipset create bypass hash:ip
    ipset create bypass6 hash:ip family inet6
    ip rule add fwmark 1001 table 1001
    ip -6 rule add fwmark 1001 table 1001
fi
EOF

# Создание скриптов для маршрутов
echo "Создание скриптов маршрутизации..."
cat << EOF > /opt/etc/ndm/ifstatechanged.d/010-bypass-table.sh
#!/bin/sh

[ "\$system_name" == "$net_interface" ] || exit 0
[ ! -z "\$(ipset --quiet list bypass)" ] || exit 0
[ "\${connected}-\${link}-\${up}" == "yes-up-up" ] || exit 0

if [ -z "\$(ip route list table 1001)" ]; then
    ip route add default dev \$system_name table 1001
fi
EOF

cat << EOF > /opt/etc/ndm/ifstatechanged.d/011-bypass6-table.sh
#!/bin/sh

[ "\$system_name" == "$net_interface" ] || exit 0
[ ! -z "\$(ipset --quiet list bypass6)" ] || exit 0
[ "\${connected}-\${link}-\${up}" == "yes-up-up" ] || exit 0

if [ -z "\$(ip -6 route list table 1001)" ]; then
    ip -6 route add default dev \$system_name table 1001
fi
EOF

# Создание скриптов для маркировки трафика
echo "Создание скриптов для маркировки трафика..."
cat << EOF > /opt/etc/ndm/netfilter.d/010-bypass.sh
#!/bin/sh

[ "\$type" == "ip6tables" ] && exit
[ "\$table" != "mangle" ] && exit
[ -z "\$(ip link list | grep $net_interface)" ] && exit
[ -z "\$(ipset --quiet list bypass)" ] && exit

if [ -z "\$(iptables-save | grep bypass)" ]; then
     iptables -w -t mangle -A PREROUTING ! -i $net_interface -m conntrack --ctstate NEW -m set --match-set bypass dst -j CONNMARK --set-mark 1001
     iptables -w -t mangle -A PREROUTING ! -i $net_interface -m set --match-set bypass dst -j CONNMARK --restore-mark
fi
EOF

cat << EOF > /opt/etc/ndm/netfilter.d/011-bypass6.sh
#!/bin/sh

[ "\$type" != "ip6tables" ] && exit
[ "\$table" != "mangle" ] && exit
[ -z "\$(ip -6 link list | grep $net_interface)" ] && exit
[ -z "\$(ipset --quiet list bypass6)" ] && exit

if [ -z "\$(ip6tables-save | grep bypass6)" ]; then
     ip6tables -w -t mangle -A PREROUTING ! -i $net_interface -m conntrack --ctstate NEW -m set --match-set bypass6 dst -j CONNMARK --set-mark 1001
     ip6tables -w -t mangle -A PREROUTING ! -i $net_interface -m set --match-set bypass6 dst -j CONNMARK --restore-mark
fi
EOF

# Создание базового списка доменов для перенаправления
echo "Создание базового списка доменов для перенаправления..."
cat << EOF > /opt/etc/AdGuardHome/ipset.conf
2ip.ru/bypass,bypass6
googlevideo.com,ggpht.com,ytimg.com,youtube.com,youtubei.googleapis.com,youtu.be,nhacmp3youtube.com,googleusercontent.com,gstatic.com/bypass,bypass6
openai.com,chatgpt.com/bypass,bypass6
bookstagram.com,carstagram.com,cdninstagram.com,chickstagram.com,ig.me,igcdn.com,igsonar.com,igtv.com,imstagram.com,imtagram.com,instaadder.com,instachecker.com,instafallow.com,instafollower.com,instagainer.com,instagda.com,instagify.com,instagmania.com,instagor.com,instagram-brand.com,instagram-engineering.com,instagram-help.com,instagram-press.com,instagram-press.net,instagram.com,instagramhashtags.net,instagramhilecim.com,instagramhilesi.org,instagramium.com,instagramizlenme.com,instagramkusu.com,instagramlogin.com,instagrampartners.com,instagramphoto.com,instagramq.com,instagramsepeti.com,instagramtips.com,instagramtr.com,instagy.com,instamgram.com,instanttelegram.com,instaplayer.net,instastyle.tv,instgram.com,oninstagram.com,online-instagram.com,onlineinstagram.com,web-instagram.net,wwwinstagram.com/bypass,bypass6
1337x.to,game4you.top,eztv.re,fitgirl-repacks.site,megashara.net,nnmclub.to,nnm-club.to,nnm-club.me,rarbg.to,rustorka.com,rutor.info,rutor.org,rutracker.cc,rutracker.org,rutracker.cc,tapochek.net,thelastgame.ru,thepiratebay.org,thepirate-bay.org,torrentgalaxy.to,torrent-games.best,torrentz2eu.org,limetorrents.info,pirateproxy-bay.com,torlock.com,torrentdownloads.me/bypass,bypass6
github.com/bypass,bypass6
EOF

# Установка прав на выполнение скриптов
echo "Установка прав на выполнение скриптов..."
chmod +x /opt/etc/init.d/S52ipset
chmod +x /opt/etc/ndm/ifstatechanged.d/010-bypass-table.sh
chmod +x /opt/etc/ndm/ifstatechanged.d/011-bypass6-table.sh
chmod +x /opt/etc/ndm/netfilter.d/010-bypass.sh
chmod +x /opt/etc/ndm/netfilter.d/011-bypass6.sh

# Перезапуск AdGuard Home
echo "Перезапуск AdGuard Home..."
/opt/etc/init.d/S99adguardhome restart

# Информационные сообщения
echo "Скрипт выполнен."
echo "Завершите настройку AdGuardHome перейдя по адресу: http://192.168.1.1:3000/"
echo "Для проверки работы перейдите на 2ip.ru, должен отображаться IP-адрес вашего VPN."
echo "Чтобы добавить домены для перенаправления, отредактируйте файл: /opt/etc/AdGuardHome/ipset.conf."
echo "После добавления доменов необходимо перезапустить AdGuard Home командой: /opt/etc/init.d/S99adguardhome restart."

# Удаляем скрипт после выполнения
rm -- "$0"
