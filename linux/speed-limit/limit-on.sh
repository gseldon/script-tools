#!/bin/bash

IFACE=$(ip route show | grep "^172\.16\." | grep -oP 'dev \K\S+' | head -1)
[ -z "$IFACE" ] && IFACE=$(ip -o addr show | awk '$2 ~ /172\.16\./{print $2;exit}' | sed 's/:$//')
[ -z "$IFACE" ] && { echo "ОШИБКА: Интерфейс не найден"; exit 1; }
echo "Интерфейс: $IFACE"

LAN_NETS="172.16.0.0/16 10.0.0.0/8"
RATE="30000kbit"
BURST="10k"

# Модуль IFB
modprobe ifb numifbs=1
# Создаем ifb0 если не существует
if ! ip link show ifb0 >/dev/null 2>&1; then
  ip link add ifb0 type ifb
fi
ip link set dev ifb0 up

# Сброс
tc qdisc del dev $IFACE root 2>/dev/null
tc qdisc del dev $IFACE ingress 2>/dev/null
tc qdisc del dev ifb0 root 2>/dev/null
iptables -t mangle -F; iptables -t mangle -X

# DOWNLOAD (IFB redirect) - только загрузка из интернета
echo "Download $RATE (IFB)"
tc qdisc add dev $IFACE handle ffff: ingress
# Перенаправляем весь входящий трафик на ifb0
# Используем простой синтаксис u32 для совместимости
tc filter add dev $IFACE parent ffff: protocol ip u32 \
  match u32 0 0 \
  action mirred egress redirect dev ifb0

tc qdisc add dev ifb0 root handle 1: htb r2q 15 default 12
tc class add dev ifb0 parent 1: classid 1:11 htb rate 1tbit burst $BURST
tc class add dev ifb0 parent 1: classid 1:12 htb rate $RATE burst $BURST
tc filter add dev ifb0 parent 1: prio 1 protocol ip handle 11 fw flowid 1:11
tc filter add dev ifb0 parent 1: prio 2 protocol ip handle 12 fw flowid 1:12

# Помечаем пакеты ДО попадания в IFB (на исходном интерфейсе)
# Локальный трафик (из локальной сети ИЛИ в локальную сеть) → mark 11 (неограниченный)
# Интернет-трафик → mark 12 (ограниченный)
# Сначала помечаем локальный трафик, затем остальной (интернет)
for LAN in $LAN_NETS; do
  # Трафик из локальной сети - не ограничиваем
  iptables -t mangle -A PREROUTING -i $IFACE -s $LAN -m mark ! --mark 11 -j MARK --set-mark 11
  # Трафик в локальную сеть - не ограничиваем
  iptables -t mangle -A PREROUTING -i $IFACE -d $LAN -m mark ! --mark 11 -j MARK --set-mark 11
done
# Весь остальной трафик (интернет) - ограничиваем (только если еще не помечен)
iptables -t mangle -A PREROUTING -i $IFACE -m mark ! --mark 11 -j MARK --set-mark 12

echo "Ограничение DOWNLOAD $RATE установлено на $IFACE (IFB активен)"
echo "Локальный трафик не ограничивается"
echo "Проверка: tc qdisc show dev $IFACE && tc qdisc show dev ifb0"

