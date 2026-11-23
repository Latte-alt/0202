# Шпаргалка на второй экран: только порядок и проверки

[← Оглавление](../README.md) · [Полная инструкция](00-start.md) · [Как запомнить](11-kak-zapomnit.md)

## Время: 60 минут на задание 1

| Минуты | Делать | Основная проверка |
|---|---|---|
| 00–04 | Proxmox, интерфейсы, Tag 100/200 | bridge, MAC, VLAN |
| 04–10 | ISP | `ping 8.8.8.8`, NAT |
| 10–24 | HQ-RTR → BR-RTR | `show ip interface brief`, пинг GRE |
| 24–33 | HQ-SRV | DNS 192.168.0.2, SSH 2027 |
| 33–40 | BR-FW | FRR, OSPF-сосед |
| 40–46 | BR-SRV | IP 192.168.4.2, SSH |
| 46–50 | HQ-CLI | DHCP VLAN 200 |
| 50–56 | Вся сеть | HQ ↔ BR, DNS, интернет |
| 56–60 | Отчёт | таблицы, проверки, сохранение |

Ориентиры условные: ожидание установки пакетов может сдвинуть график. Не забывай параллельно фиксировать доказательства для отчёта.

## Шаблон, который нужно знать наизусть

```bash
cd /etc/net/ifaces/ens18
mcedit options
echo 192.168.0.2/27 > ipv4address
echo 'default via 192.168.0.1' > ipv4route
systemctl restart network
ip -br a
```

Для DHCP — в `options` пишем `BOOTPROTO=dhcp`, файлы `ipv4address` и `ipv4route` не нужны. Подробнее: [как запомнить команды](11-kak-zapomnit.md).

## 7 IP, которые особенно важно помнить

```text
ISP -> HQ     172.16.1.1       HQ-RTR WAN 172.16.1.2
ISP -> BR     172.16.2.1       BR-RTR WAN 172.16.2.2
HQ VLAN100    192.168.0.1      HQ-SRV     192.168.0.2
HQ VLAN200    192.168.1.1      HQ-CLI     DHCP /28
BR-RTR -> FW  192.168.3.1      BR-FW out  192.168.3.2
BR-FW -> SRV  192.168.4.1      BR-SRV     192.168.4.2
GRE HQ -> BR  10.10.10.1       GRE BR     10.10.10.2
```

## Команды «проверить, что я не сломал»

```bash
# Любой ALT Linux
ip -br a; ip route; ping -c 2 IP_ШЛЮЗА

# DNS на HQ-SRV, который обязан отвечать по сети
ss -tulnp | grep ':53'
host -t A raw.githubusercontent.com 192.168.0.2

# На HQ-CLI проверить выдачу DHCP и DNS
ip -br a; cat /etc/resolv.conf
host hq-srv.au-team.irpo 192.168.0.2

# BR-FW
vtysh -c 'show ip ospf neighbor'
```

```text
! На обоих EcoRouter
show ip interface brief
show ip route
show ip ospf neighbor
show ip nat translations
```

## 5 ловушек

1. **Нет связи с шлюзом:** сначала VLAN/bridge, не DNS.
2. **HQ-CLI нет IP:** DHCP/HQ-RTR/Tag 200, не `resolv.conf`.
3. **DNS только на сервере:** `dnsmasq` не слушает `192.168.0.2:53`.
4. **BR сети нет в маршрутах:** OSPF соседа BR-FW и `redistribute connected`.
5. **После перезагрузки всё сбросилось:** `ONBOOT=yes` + `NM_CONTROLLED=no` + `write memory` на EcoRouter.

## Что не делать в первом задании

Не тратить время на Samba AD, RAID, NFS, Docker, Ansible, доменного `hquser1` и установку браузера — это **задание 2**.

[← Оглавление](../README.md)