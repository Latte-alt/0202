# 05. BR-SRV: IP, SSH и `sshuser` — около 6 минут

[← Оглавление](../README.md) · [← BR-FW](04-br-fw.md) · [Далее: HQ-CLI →](06-hq-cli.md)

**Цель:** `br-srv.au-team.irpo = 192.168.4.2/28`, шлюз `192.168.4.1`, DNS `192.168.0.2`, пользователь `sshuser` с UID `2027`, SSH `2027/tcp`.

## А. Постоянный IP

```bash
hostnamectl set-hostname br-srv.au-team.irpo
cp -a /etc/net/ifaces /root/ifaces.backup
mkdir -p /etc/net/ifaces/ens18
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
echo 192.168.4.2/28 > ipv4address
echo 'default via 192.168.4.1' > ipv4route
echo 'nameserver 192.168.0.2' > resolv.conf
systemctl restart network
ip -br -4 a
ip route
ping -c 2 192.168.4.1
ping -c 2 192.168.0.2
```

Если шлюз отвечает, а HQ-SRV нет: проверяй OSPF между BR-FW и BR-RTR, GRE и обратный маршрут до `192.168.4.0/28` на HQ-RTR. Не начинай с DNS.

## Б. SSH + пользователь + sudo (как на HQ-SRV)

```bash
apt-get update
apt-get install -y openssh-server sudo
id sshuser
# Если пользователя нет:
useradd -m -u 2027 sshuser
passwd sshuser
usermod -aG wheel sshuser
control sudo public
mkdir -p /etc/sudoers.d
mcedit /etc/sudoers
# Проверь наличие @includedir /etc/sudoers.d
mcedit /etc/sudoers.d/sshuser
# Напиши: sshuser ALL=(ALL:ALL) NOPASSWD: ALL
chmod 400 /etc/sudoers.d/sshuser
visudo -c

cp /etc/openssh/sshd_config /etc/openssh/sshd_config.bak
mcedit /etc/openssh/banner
# Напиши: Authorized access only
mcedit /etc/openssh/sshd_config
# Найди и установи Port 2027, AllowUsers sshuser,
# MaxAuthTries 2, Banner /etc/openssh/banner,
# PasswordAuthentication yes; не оставляй активных дублей
sshd -t
systemctl enable sshd
systemctl restart sshd
```

Пароль устанавливается обычной командой `passwd sshuser`. При запросе дважды введи учебный пароль `P@ssw0rd`. Не вводи `useradd` повторно, если `id sshuser` показал существующую учётную запись.

## В. DNS, время и проверка

```bash
echo 'nameserver 192.168.0.2' > /etc/resolv.conf
timedatectl set-timezone Asia/Yekaterinburg
id -u sshuser
sudo -l -U sshuser
ss -tlnp | grep ':2027'
host -t A hq-srv.au-team.irpo 192.168.0.2
host -t A raw.githubusercontent.com 192.168.0.2
ping -c 2 8.8.8.8
```

**Проверка SSH** (с HQ-SRV или другого Linux в достижимой сети):

```bash
ssh -p 2027 sshuser@192.168.4.2
```

Нужный результат: баннер `Authorized access only`, вход `sshuser`, UID `2027`, возможность `sudo -n id` без запроса пароля.

[Далее: HQ-CLI →](06-hq-cli.md)