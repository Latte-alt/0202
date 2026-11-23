# 02. EcoRouter: HQ-RTR + BR-RTR — около 14 минут

[← Оглавление](../README.md) · [← ISP](01-isp.md) · [Далее: HQ-SRV →](03-hq-srv.md)

## Что делаем

Вводим по **одной связной конфигурации на каждый маршрутизатор**, вместо десятка возвратов в консоль: интерфейсы → пользователи → VLAN → маршруты → GRE → OSPF → NAT → DHCP → время → `write memory`.

**Перед началом:** `show port brief`: `te0` должен идти к ISP, `te1` — в локальную сеть. Иначе подставь реальные порты. EcoRouter не является bash: команды вводятся **в его консоли**, без символа `$` или `#` в начале. При вставке очень длинных блоков через веб-консоль Proxmox разбивай по подсекциям, если теряются строки.

## Перед командами — 4 шаблона для запоминания

> **Не зубри два больших конфига целиком.** Учись по повторяющимся шаблонам. На EcoRouter часть команд длинная из-за синтаксиса устройства, но команды HQ и BR устроены одинаково.

**1. Начало и сохранение:** `enable` → `configure terminal` → настройки → `end` → `write memory`.

**2. Любой IP:** `interface ИМЯ` → `ip address IP/МАСКА` → `exit`.

**3. WAN:** `port te0` → `service-instance te0/isp` → `encapsulation untagged` → `connect ip interface isp` → два `exit`.

**4. GRE и OSPF:** `interface tunnel.0` → адрес туннеля → `ip tunnel ИСТОЧНИК НАЗНАЧЕНИЕ mode gre`; затем `router ospf 1` → сети `network ... area 0`.

Полный текст ниже — **эталон, чтобы проверять себя после ручного ввода**, а не блок для механического копирования. Начни с [короткого урока по запоминанию](11-kak-zapomnit.md).

## A. HQ-RTR — полный набор команд

```text
enable
configure terminal
hostname hq-rtr.au-team.irpo
ip domain-name au-team.irpo

username net_admin
 password P@ssw0rd
 role admin
exit

! WAN к ISP
interface isp
 ip address 172.16.1.2/28
exit
port te0
 service-instance te0/isp
  encapsulation untagged
  connect ip interface isp
 exit
exit

! Адреса шлюзов VLAN
interface vl100
 ip address 192.168.0.1/27
exit
interface vl200
 ip address 192.168.1.1/28
exit
interface vl999
 ip address 192.168.2.1/29
exit

! Один физический порт te1, три VLAN (tagged 802.1Q)
port te1
 service-instance te1/vl100
  encapsulation dot1q 100 exact
  rewrite pop 1
  connect ip interface vl100
 exit
 service-instance te1/vl200
  encapsulation dot1q 200 exact
  rewrite pop 1
  connect ip interface vl200
 exit
 service-instance te1/vl999
  encapsulation dot1q 999 exact
  rewrite pop 1
  connect ip interface vl999
 exit
exit

! Маршрут в интернет
ip route 0.0.0.0/0 172.16.1.1

! Туннель к BR-RTR
interface tunnel.0
 ip address 10.10.10.1/30
 ip mtu 1400
 ip tunnel 172.16.1.2 172.16.2.2 mode gre
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
exit

! Динамические маршруты: сосед только через tunnel.0
router ospf 1
 router-id 1.1.1.1
 passive-interface default
 no passive-interface tunnel.0
 network 10.10.10.0/30 area 0
 network 192.168.0.0/27 area 0
 network 192.168.1.0/28 area 0
 network 192.168.2.0/29 area 0
exit

! NAT из VLAN в сторону ISP
interface isp
 ip nat outside
exit
interface vl100
 ip nat inside
exit
interface vl200
 ip nat inside
exit
interface vl999
 ip nat inside
exit
ip nat pool HQ 192.168.0.1-192.168.0.30,192.168.1.1-192.168.1.14,192.168.2.1-192.168.2.6
ip nat source dynamic inside-to-outside pool HQ overload interface isp

! DHCP для HQ-CLI / VLAN200
ip pool CLI 192.168.1.2-192.168.1.14
dhcp-server 1
 pool CLI 1
  mask 255.255.255.240
  gateway 192.168.1.1
  dns 192.168.0.2
  domain-name au-team.irpo
 exit
exit
interface vl200
 dhcp-server 1
exit

ntp timezone utc+5
end
write memory
```

### HQ-RTR — что проверять сразу

```text
show ip interface brief
show ip route
show ip ospf neighbor
show ip nat translations
ping 172.16.1.1
```

**Пока BR-RTR не настроен — OSPF-соседа не будет, это нормально.** Пока HQ-SRV не настроен, DNS в DHCP `192.168.0.2` ещё не отвечает — это тоже нормально.

**Что важно понимать:** `te1` работает как trunk для VLAN 100/200/999; `vl100`, `vl200`, `vl999` — шлюзы подсетей; `tunnel.0` соединяет HQ с BR; OSPF узнаёт чужие сети; NAT даёт интернет; DHCP раздаёт настройки HQ-CLI.

## B. BR-RTR — полный набор команд

```text
enable
configure terminal
hostname br-rtr.au-team.irpo
ip domain-name au-team.irpo

username net_admin
 password P@ssw0rd
 role admin
exit

! WAN к ISP
interface isp
 ip address 172.16.2.2/28
exit
port te0
 service-instance te0/isp
  encapsulation untagged
  connect ip interface isp
 exit
exit

! Сеть к BR-FW
interface fw
 ip address 192.168.3.1/30
exit
port te1
 service-instance te1/fw
  encapsulation untagged
  connect ip interface fw
 exit
exit

ip route 0.0.0.0/0 172.16.2.1

! GRE к HQ-RTR — адреса источника и назначения поменяны местами
interface tunnel.0
 ip address 10.10.10.2/30
 ip mtu 1400
 ip tunnel 172.16.2.2 172.16.1.2 mode gre
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
exit

! OSPF на туннеле и на линке к BR-FW
router ospf 1
 router-id 2.2.2.2
 passive-interface default
 no passive-interface tunnel.0
 no passive-interface fw
 network 10.10.10.0/30 area 0
 network 192.168.3.0/30 area 0
exit

! NAT
interface isp
 ip nat outside
exit
interface fw
 ip nat inside
exit
ip nat pool BR 192.168.3.1-192.168.3.2,192.168.4.1-192.168.4.14
ip nat source dynamic inside-to-outside pool BR overload interface isp

ntp timezone utc+5
end
write memory
```

### BR-RTR — проверка

```text
show ip interface brief
show ip route
show ip ospf neighbor
ping 172.16.2.1
ping 10.10.10.1
```

**Пока BR-FW не настроен — его OSPF-соседа не будет.** Должен появиться сосед HQ-RTR через GRE, если ISP действительно пропускает GRE (протокол IP 47). Проверь в обе стороны:

```text
! С HQ-RTR
ping 10.10.10.2
! С BR-RTR
ping 10.10.10.1
```

## Почему на BR-RTR OSPF разрешён и на `fw`?

Требование «только нужные интерфейсы» в КИМ сформулировано не идеально: **BR-FW не сможет стать OSPF-соседом BR-RTR, если на BR-RTR интерфейс `fw` пассивный**. Поэтому в проверенной схеме из исходного репозитория соседства разрешены: HQ-RTR — только GRE, BR-RTR — GRE **и линк к BR-FW**, BR-FW — только линк к BR-RTR. Это технически необходимая часть выбранной топологии.

## Ошибки, которые теряют время

- Нет пинга `172.16.1.1` или `172.16.2.1` → перепутан `te0` или bridge ISP.
- Нет GRE-пинга → проверь внешние адреса двух роутеров, маршруты по умолчанию, IP-протокол 47 на ISP.
- OSPF не видит HQ ↔ BR → сравни MD5-ключ `P@ssw0rd`, оба GRE IP `/30`, area 0, `passive-interface`.
- HQ-CLI не получает IP → проверь VLAN Tag 200 в Proxmox и `dhcp-server 1` на `vl200`.
- Не сохраняй конфигурацию на каждом экране: один `write memory` в конце каждого маршрутизатора достаточно.

### Коротко для преподавателя

VLAN — разделение трафика, GRE — туннель между двумя площадками, OSPF — динамический обмен маршрутами, MD5 — предусмотренная КИМ проверка подлинности OSPF, NAT overload — выход нескольких устройств через один внешний IP, DHCP — автоматическая выдача IPv4 для HQ-CLI.

[Далее: HQ-SRV →](03-hq-srv.md)