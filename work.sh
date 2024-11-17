#!/bin/sh

# ������� ������ ����������� ��� ������
echo "��������� ����������:"
i=1
interfaces=$(ip a | sed -n 's/.*: \(.*\): <.*UP.*/\1/p')  # ������ �����������
interface_list=""  # ������ ��� �������� �����������
for iface in $interfaces; do
    # ���������, ���������� �� ���������, ��������� ������ 'ip: can't find device'
    if ip a show "$iface" &>/dev/null; then
        # �������� IP-����� ����������, ��������� ip a show
        ip_address=$(ip a show "$iface" | grep -oP 'inet \K[\d.]+')

        # ���� IP-����� ������, ������� ��������� � ��� IP
        if [ -n "$ip_address" ]; then
            echo "$i. $iface: $ip_address"
            interface_list="$interface_list $iface"  # ��������� ��������� � ������
            i=$((i+1))
        fi
    fi
done

# ����������� � ������������ ��� ���������� � ��������� �����
while true; do
    read -p "������� ��� ����������: " net_interface

    # ���������, ���������� �� ��������� ��� � ������ �����������
    if echo "$interface_list" | grep -qw "$net_interface"; then
        # ���� ��������� ������, ��������� ����
        echo "������ ���������: $net_interface"
        break
    else
        # ���� ������ �������� ���������, ������� ��������� �� ������
        echo "�������� �����, ���������� ������ ��� ���������� �� ������."
    fi
done

# ������� ������ ����� ����������
rm -- "$0"
