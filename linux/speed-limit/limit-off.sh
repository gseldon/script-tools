#!/bin/bash

# Определяем интерфейс так же, как в limit-on.sh
IFACE=$(ip route show | grep "^172\.16\." | grep -oP 'dev \K\S+' | head -1)
[ -z "$IFACE" ] && IFACE=$(ip -o addr show | awk '$2 ~ /172\.16\./{print $2;exit}' | sed 's/:$//')

if [ -n "$IFACE" ]; then
  echo "Снятие ограничений с $IFACE"
  # Удаляем root qdisc (если был)
  tc qdisc del dev $IFACE root 2>/dev/null
  # Удаляем ingress qdisc и все фильтры на нем
  tc qdisc del dev $IFACE ingress 2>/dev/null
  echo "Ограничение снято с $IFACE"
else
  echo "Интерфейс не найден, общий сброс"
fi

# Удаляем qdisc с ifb0
if ip link show ifb0 >/dev/null 2>&1; then
  tc qdisc del dev ifb0 root 2>/dev/null
  echo "Ограничение снято с ifb0"
fi

# Очищаем iptables mangle
iptables -t mangle -F
iptables -t mangle -X
echo "iptables mangle очищены"

echo "Все ограничения сняты"

