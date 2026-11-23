# 03. HQ-SRV: IP, DNS, SSH, sudo — около 9 минут

[← Оглавление](../README.md) · [← Маршрутизаторы](02-routers.md) · [Далее: BR-FW →](04-br-fw.md)

**Цель:** `hq-srv.au-team.irpo = 192.168.0.2/27`, шлюз `192.168.0.1`, DNS на 53/TCP+UDP, SSH на 2027, `sshuser` с UID 2027.

**Важно:** Proxmox уже ставит **VLAN Tag 100**; внутри ALT Linux нужен обычный `ens18`, без `ens18.100`. Все команды — на HQ-SRV, от `root`.

## А. Постоянный IP — простой шаблон через `mcedit`

**Учить нужно только `cd`, `mcedit`, `echo` и `systemctl restart network`.** Не обязательно запоминать длинные конструкции Bash.

```bash
hostnamectl set-hostname hq-srv.au-team.irpo
cp -a /etc/net/ifaces /root/ifaces.backup
mkdir -p /etc/net/ifaces/ens18
cd /etc/net/ifaces/ens18
mcedit options
```

В `options` запиши:

```ini
TYPE=eth
BOOTPROTO=static
NM_CONTROLLED=no
DISABLED=no
CONFIG_IPV4=yes
ONBOOT=yes
```

После F2 и F10:

```bash
echo 192.168.0.2/27 > ipv4address
echo 'default via 192.168.0.1' > ipv4route
echo 'nameserver 77.88.8.8' > resolv.conf
systemctl restart network
ip -br -4 addr
ip route
ping -c 2 192.168.0.1
ping -c 2 8.8.8.8
```

Если нет пинга шлюза: проверить VLAN Tag 100, trunk HQ-RTR и то, что адрес назначен **ens18**, а не `vlan100`.

## Б. Устанавливаем сразу всё необходимое

```bash
apt-get update
apt-get install -y dnsmasq bind-utils openssh-server sudo
```

Если пакет `sudo` или другой уже установлен — это нормально. Если установщик не находит пакет, уточни имя в репозитории ALT Linux (например, `apt-cache search ...`), не пытайся скачать случайный rpm.

## В. Пользователь `sshuser` и sudo

```bash
id sshuser
useradd -m -u 2027 sshuser
passwd sshuser
usermod -aG wheel sshuser
control sudo public
mkdir -p /etc/sudoers.d
mcedit /etc/sudoers
```

Если `id sshuser` уже показывает пользователя — **не выполняй** `useradd`. Введи пароль `P@ssw0rd` через `passwd`. В `/etc/sudoers` проверь строку `@includedir /etc/sudoers.d` (или эквивалентную `#includedir`).

```bash
mcedit /etc/sudoers.d/sshuser
```

Впиши строку:

```text
sshuser ALL=(ALL:ALL) NOPASSWD: ALL
```

Проверь:

```bash
chmod 400 /etc/sudoers.d/sshuser
visudo -c
id -u sshuser
```

UID должен быть `2027`. Не оставляй ошибку в `visudo -c`.

## Г. SSH: порт 2027, две попытки, баннер

```bash
cp /etc/openssh/sshd_config /etc/openssh/sshd_config.bak
mcedit /etc/openssh/banner
# Напиши: Authorized access only
mcedit /etc/openssh/sshd_config
# Найди и измени вручную строки Port, AllowUsers,
# MaxAuthTries, Banner, PasswordAuthentication.
# Не оставляй дублирующих активных значений.
# Нужны: Port 2027, AllowUsers sshuser, MaxAuthTries 2,
# Banner /etc/openssh/banner, PasswordAuthentication yes
sshd -t
systemctl enable sshd
systemctl restart sshd
ss -tlnp | grep ':2027'
```

Не отключай доступ через консоль Proxmox! Если `sshd -t` выводит ошибку, исправь её **до** перезапуска. Проверка с HQ-CLI позже: `ssh -p 2027 sshuser@192.168.0.2`.

## Д. DNS: полная таблица имён и обратные записи

Это самый важный блок: **не допускай ситуации, когда DNS работает только на 127.0.0.1**. В исходном автонастроечном скрипте у тебя такая проблема уже была.

```bash
cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
mcedit /etc/dnsmasq.conf
```

Впиши в файл следующие строки (без служебных команд `cat`/`EOF`):

```ini
# DNS для учебного домена au-team.irpo
listen-address=127.0.0.1,192.168.0.2
no-hosts
no-resolv
domain-needed
server=77.88.8.7
server=77.88.8.3
cache-size=1000
local-ttl=60

# По таблице 3: эти две записи требуют A и PTR
host-record=hq-srv.au-team.irpo,192.168.0.2
host-record=br-srv.au-team.irpo,192.168.4.2

# Только A
address=/hq-rtr.au-team.irpo/192.168.0.1
address=/br-rtr.au-team.irpo/192.168.3.1
address=/br-fw.au-team.irpo/192.168.3.2
address=/hq-cli.au-team.irpo/192.168.1.2
address=/docker.au-team.irpo/172.16.1.1
address=/web.au-team.irpo/172.16.2.1
```

```bash
dnsmasq --test
systemctl enable --now dnsmasq
systemctl restart dnsmasq
ss -tulnp | grep ':53'
```

**Разъяснение:** `listen-address` открывает DNS на `192.168.0.2`; `no-hosts` исключает ложную запись `127.0.1.1` из `/etc/hosts`; `host-record` создаёт записи для имён и обратных запросов; `server=` — внешние DNS-серверы пересылки.

Проверяем **обязательно**, до перехода к следующей ВМ:

```bash
host -t A hq-srv.au-team.irpo 192.168.0.2
host -t A br-srv.au-team.irpo 192.168.0.2
host 192.168.0.2 192.168.0.2
host 192.168.4.2 192.168.0.2
host -t A raw.githubusercontent.com 192.168.0.2
```

Ожидаем A `192.168.0.2`, A `192.168.4.2`, два PTR и IP-адреса GitHub.

После успеха меняем **постоянный** DNS HQ-SRV на собственный:

```bash
printf '%s\n' 'nameserver 127.0.0.1' 'search au-team.irpo' > /etc/net/ifaces/ens18/resolv.conf
printf '%s\n' 'nameserver 127.0.0.1' 'search au-team.irpo' > /etc/resolv.conf
```

> DHCP выдаёт HQ-CLI адрес из диапазона. Если клиент получит НЕ `192.168.1.2`, после шага HQ-CLI поменяй строку `address=/hq-cli...` на фактический адрес и перезапусти `dnsmasq`.

## Е. Часовой пояс и финальная проверка

```bash
timedatectl set-timezone Asia/Yekaterinburg
hostname -f
ip -br -4 a
ss -tulnp | grep ':53'
ss -tlnp | grep ':2027'
getent ahostsv4 raw.githubusercontent.com
timedatectl | grep 'Time zone'
```

Если всё верно — HQ-SRV готов.

[Далее: BR-FW →](04-br-fw.md)