# 01. ISP — настраиваем вручную и запоминаем

[← Оглавление](../README.md) · [Как запомнить команды](11-kak-zapomnit.md) · [Далее: EcoRouter](02-routers.md)

**Задача:** WAN по DHCP, LAN к HQ `172.16.1.1/28`, LAN к BR `172.16.2.1/28`, включить пересылку и NAT.

> Пример: `ens18` — WAN, `ens19` — HQ, `ens20` — BR. **Проверь порядок сетевых карт в Proxmox по MAC.** Работай в консоли Proxmox как root. Не переписывай рабочую WAN-конфигурацию, если DHCP уже работает.

## 1. Имя и адреса

```bash
hostnamectl set-hostname isp
cp -a /etc/net/ifaces /root/ifaces.backup
cd /etc/net/ifaces
mkdir -p ens19 ens20
cd ens19
mcedit options
```

В `options` впиши простой шаблон:

```ini
TYPE=eth
BOOTPROTO=static
NM_CONTROLLED=no
DISABLED=no
CONFIG_IPV4=yes
ONBOOT=yes
```

Сохрани **F2**, выйди **F10**. Укажи IP:

```bash
echo 172.16.1.1/28 > ipv4address
cd ../ens20
cp ../ens19/options options
echo 172.16.2.1/28 > ipv4address
```

С WAN (`ens18`) должен работать DHCP: `BOOTPROTO=dhcp`. Если `ens19/ens20` ранее имели чужие маршруты, открой их папки и удали только устаревший `ipv4route`.

**Один перезапуск после всех настроек:**

```bash
systemctl restart network
ip -br a
ip route
ping -c 2 8.8.8.8
```

Если WAN не получает адрес по DHCP — сначала проверь мост Proxmox, а не добавляй выдуманный шлюз.

## 2. Разрешаем пересылку пакетов

Сначала включи прямо сейчас:

```bash
sysctl -w net.ipv4.ip_forward=1
```

Чтобы сохранилось после перезагрузки:

```bash
mcedit /etc/sysctl.conf
```

Добавь или исправь строку:

```ini
net.ipv4.ip_forward = 1
```

## 3. NAT

```bash
apt-get update
apt-get install iptables
```

На учебном ISP с внешним `ens18`:

```bash
iptables -t nat -A POSTROUTING -o ens18 -j MASQUERADE
iptables -t nat -S
iptables -S FORWARD
```

**Запомни частями:** `iptables` → `-t nat` → `-A POSTROUTING` → `-o ens18` → `-j MASQUERADE`. Добавляй только если такого правила ещё нет: повторное выполнение `-A` создаёт дубликат. NAT не заменяет разрешение пересылки: если цепочка FORWARD блокирует пакеты, нужны разрешающие правила по политике изолированного учебного стенда.

Сохранение:

```bash
iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
```

Проверяй, что служба действительно поднимает правило после перезагрузки.

## 4. Часовой пояс

```bash
timedatectl set-timezone Asia/Yekaterinburg
```

## 5. Что показать

```bash
ip -br a
ip route
sysctl net.ipv4.ip_forward
iptables -t nat -S
```

**Запомнить:** `ISP = 3 интерфейса + forwarding + NAT`. На защите скажи: «ISP соединяет маршрутизаторы с внешней сетью, NAT подменяет адрес источника, forwarding разрешает пересылку».
