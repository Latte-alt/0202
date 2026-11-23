# 01. ISP: интернет, три интерфейса, NAT — около 6 минут

[← Оглавление](../README.md) · [← Подготовка](00-start.md) · [Далее: маршрутизаторы →](02-routers.md)

## Цель

WAN получает настройки по DHCP, порт к HQ — `172.16.1.1/28`, к BR — `172.16.2.1/28`. Включить IPv4 forwarding и MASQUERADE наружу.

**Предполагаем:** `ens18` = WAN, `ens19` = HQ, `ens20` = BR. **Сначала проверь MAC-адреса в Proxmox**. Если иначе — замени имена во всём блоке.

## Быстрый блок (root)

```bash
hostnamectl set-hostname isp
cp -a /etc/net/ifaces /root/ifaces.backup
mkdir -p /etc/net/ifaces/{ens18,ens19,ens20}

# WAN: DHCP
cat > /etc/net/ifaces/ens18/options <<'EOF'
TYPE=eth
BOOTPROTO=dhcp
NM_CONTROLLED=no
DISABLED=no
CONFIG_IPV4=yes
CONFIG_IPV6=no
ONBOOT=yes
EOF

# HQ: статический интерфейс
cat > /etc/net/ifaces/ens19/options <<'EOF'
TYPE=eth
BOOTPROTO=static
NM_CONTROLLED=no
DISABLED=no
CONFIG_IPV4=yes
CONFIG_IPV6=no
ONBOOT=yes
EOF
printf '%s\n' '172.16.1.1/28' > /etc/net/ifaces/ens19/ipv4address

# BR: статический интерфейс
cp /etc/net/ifaces/ens19/options /etc/net/ifaces/ens20/options
printf '%s\n' '172.16.2.1/28' > /etc/net/ifaces/ens20/ipv4address

# Сторонние статические маршруты на ISP-HQ/BR не нужны
rm -f /etc/net/ifaces/ens19/ipv4route /etc/net/ifaces/ens20/ipv4route

# Включаем пересылку сейчас и после перезагрузки
sysctl -w net.ipv4.ip_forward=1
printf '%s\n' 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/90-demo-forward.conf
systemctl restart network

# Проверяем, что WAN получил шлюз и интернет
ip -br -4 a
ip route
ping -c 2 8.8.8.8
```

Если WAN не получает DHCP, **остановись и проверь подключение к учебной сети**; не добавляй случайный gateway вручную.

## NAT — отдельный короткий блок

```bash
apt-get update
apt-get install -y iptables
# Подставь реальный внешний интерфейс WAN вместо ens18, если отличается.
iptables -t nat -C POSTROUTING -o ens18 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o ens18 -j MASQUERADE
mkdir -p /etc/sysconfig
iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
iptables -t nat -S
iptables -S FORWARD
```

Если FORWARD имеет политику DROP или запрещающий firewall, нужно разрешить пересылку для двух учебных сегментов с учётом политики стенда. **Не сбрасывай правила на общей машине провайдера**. На изолированной тестовой ВМ ISP иногда удобно временно разрешить FORWARD, но для финального решения лучше ограничить его конкретными интерфейсами.

**Результат:** `ens19` и `ens20` — статические, `ens18` — DHCP, ISP может пересылать пакеты. Правило NAT сохраняется в `/etc/sysconfig/iptables`; после перезагрузки проверь, что сервис iptables действительно загрузил его (`iptables -t nat -S`).

## Быстрая проверка

```bash
ip -br -4 a
ip route | grep default
sysctl net.ipv4.ip_forward
iptables -t nat -S | grep MASQUERADE
ping -c 2 8.8.8.8
```

После настройки обоих роутеров дополнительно проверь, что ISP отвечает на `ping 172.16.1.2` и `ping 172.16.2.2`.

## Что объяснить на защите

`MASQUERADE` заменяет частный адрес источника внешним адресом ISP. `net.ipv4.ip_forward=1` разрешает маршрутизацию между интерфейсами. WAN-шлюз приходит через DHCP; две внутренние сети ISP непосредственно подключены.

[Далее: маршрутизаторы →](02-routers.md)