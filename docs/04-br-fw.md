# 04. BR-FW: шлюз филиала и OSPF — около 7 минут

[← Оглавление](../README.md) · [← HQ-SRV](03-hq-srv.md) · [Далее: BR-SRV →](05-br-srv.md)

**Цель:** BR-FW — Linux-маршрутизатор между BR-RTR и BR-SRV. Через FRRouting (FRR) он участвует в OSPF с BR-RTR, публикуя сеть `192.168.4.0/28`.

**Проверить NIC в Proxmox:** `ens18` → BR-RTR (`192.168.3.2/30`), `ens19` → BR-SRV (`192.168.4.1/28`). Если иначе — замени имена.

## А. Два интерфейса, один маршрут, один перезапуск

```bash
hostnamectl set-hostname br-fw.au-team.irpo
cp -a /etc/net/ifaces /root/ifaces.backup
mkdir -p /etc/net/ifaces/{ens18,ens19}
cd /etc/net/ifaces/ens18
mcedit options
```

В файл `options` впиши:

```ini
TYPE=eth
BOOTPROTO=static
NM_CONTROLLED=no
DISABLED=no
CONFIG_IPV4=yes
ONBOOT=yes
```

После F2 и F10 продолжи:

```bash
cp /etc/net/ifaces/ens18/options /etc/net/ifaces/ens19/options
echo 192.168.3.2/30 > ipv4address
echo 'default via 192.168.3.1' > ipv4route
cd ../ens19
echo 192.168.4.1/28 > ipv4address
rm -f /etc/net/ifaces/ens19/ipv4route
echo 'nameserver 77.88.8.8' > /etc/net/ifaces/ens18/resolv.conf

sysctl -w net.ipv4.ip_forward=1
mcedit /etc/sysctl.conf
# Добавь net.ipv4.ip_forward = 1
systemctl restart network

ip -br -4 a
ip route
ping -c 2 192.168.3.1
ping -c 2 8.8.8.8
```

Если пинг соседнего `192.168.3.1` не проходит — проблема в bridge/интерфейсе/BR-RTR, а не в OSPF. Если пинг шлюза есть, но нет выхода наружу — проверить NAT на BR-RTR/ISP, политику FORWARD, маршрут по умолчанию.

## Б. OSPF через FRR

```bash
apt-get update
apt-get install -y frr
cp /etc/frr/frr.conf /etc/frr/frr.conf.bak 2>/dev/null || true
mcedit /etc/frr/daemons
# Найди ospfd=no и замени на ospfd=yes
mcedit /etc/frr/frr.conf
# В файл впиши строки из следующего блока:
```

```text
frr defaults traditional
hostname br-fw
log syslog informational
!
router ospf
 ospf router-id 3.3.3.3
 redistribute connected
 network 192.168.3.0/30 area 0
!
line vty
!
```

```bash
chown frr:frr /etc/frr/frr.conf
systemctl enable --now frr
systemctl restart frr
```

**Почему только `192.168.3.0/30` в network?** Потому что OSPF-соседство нам нужно только на интерфейсе к BR-RTR. Команда `redistribute connected` распространяет информацию о подключённой сети `192.168.4.0/28` без OSPF-соседства на BR-SRV.

### Проверка

```bash
vtysh -c 'show ip ospf neighbor'
vtysh -c 'show ip ospf route'
vtysh -c 'show running-config'
ip route
```

Ожидаем соседа BR-RTR с router ID `2.2.2.2`. Если нет соседа: проверить `systemctl status frr`, `ospfd=yes`, сеть `/30` с обеих сторон, правила firewall и настройку `no passive-interface fw` на BR-RTR.

## В. DNS и время после успешного OSPF

```bash
mcedit /etc/net/ifaces/ens18/resolv.conf
# Напиши nameserver 192.168.0.2
echo 'nameserver 192.168.0.2' > /etc/resolv.conf
timedatectl set-timezone Asia/Yekaterinburg
host hq-srv.au-team.irpo 192.168.0.2
ping -c 2 192.168.0.2
```

**Не путай:** BR-FW — Linux с FRR, а не EcoRouter. В задании на нём нужно запустить OSPF только на направлении к BR-RTR, а не на обоих интерфейсах.

[Далее: BR-SRV →](05-br-srv.md)