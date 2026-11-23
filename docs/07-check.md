# 07. Проверка всех 11 пунктов — около 6 минут

[← Оглавление](../README.md) · [← HQ-CLI](06-hq-cli.md) · [Далее: Отчёт →](08-report.md)

## Моментальная проверка: что уже готово?

| № | Требование КИМ | Где смотреть | Что нужно увидеть |
|---|---|---|---|
| 1 | Имена, IPv4 и маски | `hostname -f`, `ip -br -4 a`, `show ip interface brief` | адреса из [таблицы](../README.md) |
| 2 | ISP WAN DHCP, интернет, NAT | ISP: `ip r`, `iptables -t nat -S`, `ping 8.8.8.8` | default через DHCP, MASQUERADE |
| 3 | `sshuser` UID 2027; `net_admin` | Linux: `id sshuser`, `sudo -l -U sshuser`; EcoRouter `show running-config` | имя/UID/права |
| 4 | VLAN 100 / 200 / 999 | Proxmox tags, HQ-RTR: `show running-config` | теги и интерфейсы `vl100/200/999` |
| 5 | SSH 2027, 2 попытки, баннер | `ss -tlnp`, `sshd -T`, реальный `ssh -p 2027` | `AllowUsers sshuser`, banner |
| 6 | GRE `10.10.10.0/30` | HQ-RTR: `ping 10.10.10.2` | туннель доступен |
| 7 | OSPF + MD5 | EcoRouter: `show ip ospf neighbor`, BR-FW `vtysh ...` | соседства и маршруты между офисами |
| 8 | NAT HQ-RTR/BR-RTR | `show ip nat translations`, пинги наружу | клиенты имеют интернет |
| 9 | DHCP HQ-CLI | HQ-CLI: `ip -br a`, `ip r`, `cat /etc/resolv.conf` | IP из `192.168.1.2–14`, шлюз `.1`, DNS `192.168.0.2` |
| 10 | DNS A / PTR, пересылка | `host ... 192.168.0.2` | все имена, 2 PTR и внешний DNS |
| 11 | Часовой пояс | Linux `timedatectl`, EcoRouter `show running-config` | UTC+5 (если экзамен в Башкортостане) |

## Быстрые группы команд (можно скопировать)

### На HQ-SRV

```bash
hostname -f
ip -br -4 a
ip route
id -u sshuser
sudo -l -U sshuser
ss -tlnp | grep ':2027'
ss -tulnp | grep ':53'
host -t A hq-srv.au-team.irpo 192.168.0.2
host -t A br-srv.au-team.irpo 192.168.0.2
host 192.168.0.2 192.168.0.2
host 192.168.4.2 192.168.0.2
host -t A raw.githubusercontent.com 192.168.0.2
ping -c 2 192.168.4.2
timedatectl
```

### На HQ-CLI

```bash
ip -br -4 a
ip route
cat /etc/resolv.conf
ping -c 2 192.168.1.1
ping -c 2 192.168.0.2
ping -c 2 192.168.4.2
ping -c 2 8.8.8.8
host hq-srv.au-team.irpo 192.168.0.2
```

### На BR-FW

```bash
sysctl net.ipv4.ip_forward
vtysh -c 'show ip ospf neighbor'
vtysh -c 'show ip ospf route'
ping -c 2 192.168.0.2
```

### На EcoRouter

```text
show ip interface brief
show ip route
show ip ospf neighbor
show ip nat translations
show running-config
```

## Диагностика за 30 секунд

| Симптом | Проверяй первым | Типичный виновник |
|---|---|---|
| HQ-SRV не пингует `192.168.0.1` | IP `ens18`, Proxmox Tag=100, `vl100` | VLAN либо bridge |
| HQ-CLI не получает IP | Tag=200, DHCP на HQ-RTR `vl200` | VLAN/DHCP, не DNS |
| `ping 8.8.8.8` есть, имя GitHub не открывается | `host ... 192.168.0.2`, `cat /etc/resolv.conf` | DNS |
| DNS работает на HQ-SRV, но не на HQ-CLI | `ss -tulnp | grep :53` на HQ-SRV | dnsmasq слушает только 127.0.0.1 |
| DNS отдаёт `127.0.1.1` для HQ-SRV | `/etc/hosts`, `dnsmasq no-hosts` | неправильный ответ A |
| HQ ↔ BR не пингуются | GRE `ping 10.10.10.2`, `show ip ospf neighbor` | OSPF/маршрутизация |
| BR-SRV не выходит в интернет | BR-FW `ip_forward`, BR-RTR NAT, ISP NAT | нет маршрута/трансляции |
| SSH connection refused | `ss -tlnp | grep 2027`, `sshd -t` | sshd/порт/firewall |
| SSH permission denied | `AllowUsers sshuser`, UID, пароль | логин/пароль/ограничения |
| После перезагрузки пропал IP | `/etc/net/ifaces/*/options` | неправильный network manager |
| OSPF сосед BR-FW отсутствует | `vtysh`, `ospfd=yes`, `no passive-interface fw` | FRR / OSPF |

## Важные нюансы

- Если внешний интернет заблокирован экзаменационной сетью, локальные DNS и GRE/OSPF всё равно можно проверять отдельно. Не объявляй интернет рабочим без реальной проверки.
- `iptables -S INPUT` **не проверяет все firewall-правила**: отдельно смотри FORWARD, возможные `nftables` и фильтры Proxmox.
- Пинг не доказывает доступность TCP/UDP 53 или SSH: проверяй непосредственно `host`, `ss`, `ssh`.
- Не запускай сомнительные массовые `iptables -F`, `ip addr flush`, `nmcli con down` на работающем стенде просто ради эксперимента.

[Далее: Отчёт →](08-report.md)