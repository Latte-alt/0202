# 06. HQ-CLI: DHCP и проверка офиса — около 4 минут

[← Оглавление](../README.md) · [← BR-SRV](05-br-srv.md) · [Далее: Проверка →](07-check.md)

**Цель:** HQ-CLI автоматически получает IP `/28`, шлюз `192.168.1.1`, DNS `192.168.0.2` и доменный суффикс `au-team.irpo`.

**В Proxmox на NIC HQ-CLI должен стоять `VLAN Tag 200`!** В самой ALT Linux не создавать `ens18.200`. Не применять скрипт `demo.sh`: из-за выбора NetworkManager он ранее выдавал ошибку `settings plugin does not support modifying connections`.

## Настройка etcnet одним блоком (root)

```bash
hostnamectl set-hostname hq-cli.au-team.irpo
cp -a /etc/net/ifaces /root/ifaces.backup
mkdir -p /etc/net/ifaces/ens18
cat > /etc/net/ifaces/ens18/options <<'EOF'
TYPE=eth
BOOTPROTO=dhcp
NM_CONTROLLED=no
DISABLED=no
CONFIG_IPV4=yes
CONFIG_IPV6=no
ONBOOT=yes
EOF
# Убираем возможные старые статические настройки этого интерфейса
rm -f /etc/net/ifaces/ens18/ipv4address /etc/net/ifaces/ens18/ipv4route
systemctl restart network
sleep 3
ip -br -4 a
ip route
cat /etc/resolv.conf
```

Убедись, что адрес попал в диапазон `192.168.1.2–192.168.1.14`. Если DHCP не выдал адрес, проверяй Proxmox Tag 200 и DHCP-сервер на `vl200` HQ-RTR, а не DNS.

## Проверяем всю цепочку

```bash
ping -c 2 192.168.1.1
ping -c 2 192.168.0.2
ping -c 2 192.168.4.2
ping -c 2 8.8.8.8
host -t A hq-srv.au-team.irpo 192.168.0.2
host -t A raw.githubusercontent.com 192.168.0.2
getent ahostsv4 raw.githubusercontent.com
```

На настоящей сдаче сеть HQ-CLI должна работать **через DNS HQ-SRV**, а не постоянно использовать внешний `77.88.8.8`. Если `host ... 192.168.0.2` работает, а обычный `getent` — нет, проверь `/etc/resolv.conf` и систему его формирования. Чтобы быстро проверить без перезапуска сети:

```bash
printf '%s\n' 'nameserver 192.168.0.2' 'search au-team.irpo' > /etc/resolv.conf
getent ahostsv4 raw.githubusercontent.com
```

Эта команда меняет текущий resolver, **но не исправляет DHCP навсегда**. Для постоянной настройки проверь, что HQ-RTR выдаёт нужную опцию DNS и клиент сохраняет её после переполучения адреса.

## Если адрес HQ-CLI не равен `192.168.1.2`

На **HQ-SRV** поправь только DNS-запись `hq-cli` в `/etc/dnsmasq.conf`: замени `192.168.1.2` на реальный адрес из `ip -br -4 a` на HQ-CLI, затем выполни `dnsmasq --test && systemctl restart dnsmasq`. После этого:

```bash
host hq-cli.au-team.irpo 192.168.0.2
```

## Проверяем SSH как внешний пользователь

```bash
ssh -p 2027 sshuser@192.168.0.2
```

Пароль по заданию: `P@ssw0rd`. Ожидается баннер и успешный вход.

## Важное отличие от задания 2

**Задание 1 НЕ требует вводить HQ-CLI в домен Samba.** Это уже другое задание. Не теряй время на `system-auth`, SSSD и `hquser1` во время первого задания.

[Далее: Проверка →](07-check.md)