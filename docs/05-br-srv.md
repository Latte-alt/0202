# 05. BR-SRV: IP, SSH и `sshuser` — около 6 минут

[← Оглавление](../README.md) · [← BR-FW](04-br-fw.md) · [Далее: HQ-CLI →](06-hq-cli.md)

**Цель:** `br-srv.au-team.irpo = 192.168.4.2/28`, шлюз `192.168.4.1`, DNS `192.168.0.2`, пользователь `sshuser` с UID `2027`, SSH `2027/tcp`.

## А. Постоянный IP

```bash
hostnamectl set-hostname br-srv.au-team.irpo
cp -a /etc/net/ifaces /root/ifaces.backup
mkdir -p /etc/net/ifaces/ens18
cat > /etc/net/ifaces/ens18/options <<'EOF'
TYPE=eth
BOOTPROTO=static
NM_CONTROLLED=no
DISABLED=no
CONFIG_IPV4=yes
CONFIG_IPV6=no
ONBOOT=yes
EOF
printf '%s\n' '192.168.4.2/28' > /etc/net/ifaces/ens18/ipv4address
printf '%s\n' 'default via 192.168.4.1' > /etc/net/ifaces/ens18/ipv4route
printf '%s\n' 'nameserver 192.168.0.2' 'search au-team.irpo' > /etc/net/ifaces/ens18/resolv.conf
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
id sshuser >/dev/null 2>&1 || useradd -m -u 2027 -s /bin/bash sshuser
echo 'sshuser:P@ssw0rd' | chpasswd
usermod -aG wheel sshuser
control sudo public 2>/dev/null || true
mkdir -p /etc/sudoers.d
grep -Eq '^[@#]includedir[[:space:]]+/etc/sudoers.d' /etc/sudoers || echo '@includedir /etc/sudoers.d' >> /etc/sudoers
printf '%s\n' 'sshuser ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/sshuser
chmod 400 /etc/sudoers.d/sshuser
visudo -c

cp /etc/openssh/sshd_config /etc/openssh/sshd_config.bak
printf '%s\n' 'Authorized access only' > /etc/openssh/banner
sed -i -E '/^[[:space:]]*#?[[:space:]]*(Port|AllowUsers|MaxAuthTries|Banner|PasswordAuthentication)[[:space:]]/d' /etc/openssh/sshd_config
{ printf '%s\n' 'Port 2027' 'AllowUsers sshuser' 'MaxAuthTries 2' 'Banner /etc/openssh/banner' 'PasswordAuthentication yes'; cat /etc/openssh/sshd_config; } > /etc/openssh/sshd_config.new
mv /etc/openssh/sshd_config.new /etc/openssh/sshd_config
sshd -t && systemctl enable --now sshd && systemctl restart sshd
```

В команде `echo 'sshuser:P@ssw0rd' | chpasswd` демонстрационный пароль вводится напрямую ради скорости учебного стенда. В рабочей сети так не делай: используй интерактивный `passwd`.

## В. DNS, время и проверка

```bash
printf '%s\n' 'nameserver 192.168.0.2' 'search au-team.irpo' > /etc/resolv.conf
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