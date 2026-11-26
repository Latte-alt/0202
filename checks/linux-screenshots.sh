#!/usr/bin/env bash
# bash linux-screenshots.sh TASK ROLE
set -u

usage() {
    printf '%s\n' \
        'Запуск: bash linux-screenshots.sh ЗАДАНИЕ МАШИНА' \
        '1: isp br-fw hq-srv br-srv hq-cli' \
        '2: isp hq-srv br-srv hq-cli hq-cli-user' \
        'Для hq-cli-user сначала войди на HQ-CLI доменным пользователем hquser1.' \
        'Для остальных ролей открой терминал root на соответствующей машине.' \
        'Адреса можно переопределить через HQ_SRV_IP, BR_SRV_IP, HQ_RTR_WAN и BR_RTR_WAN.'
}

case "${1:-} ${2:-}" in
    '1 isp'|'1 br-fw'|'1 hq-srv'|'1 br-srv'|'1 hq-cli'|\
    '2 isp'|'2 hq-srv'|'2 br-srv'|'2 hq-cli'|'2 hq-cli-user') ;;
    '--help ' | '-h ') usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

task=$1
role=$2
if [[ $role == hq-cli-user ]]; then
    account=$(id -un)
    case "${account,,}" in
        hquser1|hquser1@*|*\\hquser1) ;;
        *) printf 'Войди как hquser1. Текущая учётная запись: %s\n' "$account" >&2; exit 2 ;;
    esac
elif (( EUID != 0 )); then
    printf 'Открой терминал root командой su - и повтори запуск.\n' >&2
    exit 2
fi

if ! { exec 3</dev/tty; }; then
    printf 'Для пауз нужен интерактивный терминал.\n' >&2
    exit 2
fi

hq_srv=${HQ_SRV_IP:-192.168.0.2}
br_srv=${BR_SRV_IP:-192.168.4.2}
hq_wan=${HQ_RTR_WAN:-172.16.1.2}
br_wan=${BR_RTR_WAN:-172.16.2.2}
host_name=$(hostname)
frame=0
trap 'exit 130' INT

pause() {
    local answer
    printf '\nСделай скриншот. Enter — дальше, q — выход: '
    IFS= read -r answer <&3 || exit 0
    case "$answer" in q|Q) exit 0 ;; esac
}

title() {
    frame=$((frame + 1))
    printf '\n── Задание %s | %s (%s) | кадр %02d | %s ──\n' \
        "$task" "$role" "$host_name" "$frame" "$1"
}

run() {
    local arg status
    printf '\n$'
    for arg in "$@"; do printf ' %q' "$arg"; done
    printf '\n'
    "$@" <&3
    status=$?
    if (( status != 0 )); then printf '[Код завершения: %s]\n' "$status"; fi
}

http() {
    run curl -sS --connect-timeout 5 --max-time 15 -o /dev/null -w 'HTTP %{http_code}\n' "$1"
}

ssh_check() {
    run ssh -o ConnectTimeout=5 -o NumberOfPasswordPrompts=1 -p 2027 "sshuser@$1" "$2"
}

chrony_client() {
    title '4. NTP-клиент'
    run chronyc -n sources -v
    run chronyc tracking
    pause
}

if [[ $task == 1 ]]; then
    title 'Имя устройства, адреса, маршруты и часовой пояс'
    run hostname
    run ip -br -4 addr
    run ip -4 route
    run timedatectl show -p Timezone
    pause
fi

case "$task $role" in
    '1 isp')
        title 'NAT и пересылка IPv4'
        run iptables -t nat -S
        run sysctl net.ipv4.ip_forward
        pause
        ;;
    '1 br-fw')
        title 'Соседи и интерфейсы OSPF'
        run vtysh -c 'show ip ospf neighbor'
        run vtysh -c 'show ip ospf interface'
        pause
        title 'Маршруты OSPF'
        run vtysh -c 'show ip route ospf'
        pause
        ;;
    '1 hq-srv'|'1 br-srv')
        title 'Учётная запись, параметры и баннер SSH'
        run id sshuser
        run bash -c 'sshd -T | grep -E "^(port|allowusers|maxauthtries|banner) "'
        run bash -c 'banner=$(sshd -T | awk '\''$1 == "banner" {print $2; exit}'\''); if [[ $banner == /* ]]; then cat -- "$banner"; fi'
        pause
        if [[ $role == hq-srv ]]; then
            title 'DNS: A-записи устройств'
            for name in hq-rtr br-rtr br-fw hq-srv hq-cli br-srv docker web; do
                run host -W 3 -t A "$name.au-team.irpo" 127.0.0.1
            done
            pause
            title 'DNS: обратные и внешние запросы'
            run host -W 3 "$hq_srv" 127.0.0.1
            run host -W 3 "$br_srv" 127.0.0.1
            run host -W 3 ya.ru 127.0.0.1
            pause
        else
            title 'Связь BR → HQ и выход в интернет'
            run ping -c 3 -W 2 "$hq_srv"
            run ping -c 3 -W 2 77.88.8.8
            pause
        fi
        ;;
    '1 hq-cli')
        title 'DHCP и DNS клиента'
        if command -v nmcli >/dev/null; then
            run nmcli -f GENERAL.DEVICE,IP4,DHCP4 device show
        else
            run ip -4 addr
        fi
        run cat /etc/resolv.conf
        pause
        title 'Связь HQ → BR и выход в интернет'
        run ping -c 3 -W 2 "$br_srv"
        run ping -c 3 -W 2 77.88.8.8
        pause
        title 'SSH и sudo на HQ-SRV'
        ssh_check "$hq_srv" 'hostname; id; sudo -n id'
        pause
        title 'SSH и sudo на BR-SRV'
        ssh_check "$br_srv" 'hostname; id; sudo -n id'
        pause
        ;;
    '2 isp')
        title '4. NTP-сервер ISP'
        run systemctl is-active chronyd
        run grep -E '^[[:space:]]*(pool|server|local|allow)[[:space:]]' /etc/chrony.conf
        run chronyc -n sources
        run chronyc tracking
        pause
        title '8. HTTP и SSH через HQ-RTR'
        http "http://$hq_wan:8080/"
        ssh_check "$hq_wan" 'hostname; id'
        pause
        title '8. HTTP и SSH через BR-RTR'
        http "http://$br_wan:8080/"
        ssh_check "$br_wan" 'hostname; id'
        pause
        ;;
    '2 hq-srv')
        title '2. Диски и состояние RAID 0'
        run lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
        run cat /proc/mdstat
        run mdadm --detail /dev/md0
        pause
        title '2. Автомонтирование массива в /raid'
        run grep -E '^[[:space:]]*ARRAY' /etc/mdadm.conf
        run grep -E '[[:space:]]/raid[[:space:]]' /etc/fstab
        run findmnt /raid
        pause
        title '3. Экспорт NFS'
        run cat /etc/exports
        run exportfs -v
        pause
        chrony_client
        title '7. Apache, MariaDB и файлы сайта'
        run bash -c 'systemctl is-active httpd2 || systemctl is-active apache2'
        run bash -c 'systemctl is-active mariadb || systemctl is-active mysqld'
        run ls -l /var/www/html/index.php /var/www/html/logo.png
        http http://127.0.0.1/
        pause
        title '7. Подключение пользователя web к базе webdb'
        run mysql -u web -p -D webdb -e 'SELECT CURRENT_USER(), DATABASE(); SHOW TABLES;'
        pause
        ;;
    '2 br-srv')
        title '1. Samba: компьютер, пользователи и группа'
        run samba-tool computer list
        run bash -c 'samba-tool user list | sort | grep -E "^hquser[1-5]$"'
        run samba-tool group listmembers hq
        pause
        title '1. Политика паролей Samba'
        run samba-tool domain passwordsettings show
        pause
        chrony_client
        title '5. Инвентарь Ansible'
        if cd /etc/ansible; then
            run pwd
            run ansible-inventory --graph
        fi
        pause
        title '5. Ansible ping на четырёх машинах'
        if [[ $PWD == /etc/ansible ]]; then
            run timeout 180 ansible all -m ping
        fi
        pause
        title '6. Файл Compose и образы'
        run ls -l /root/testapp/compose.yaml
        if [[ -f /root/testapp/compose.yaml ]]; then
            if docker compose version >/dev/null 2>&1; then
                run docker compose -f /root/testapp/compose.yaml config --services
            else
                run docker-compose -f /root/testapp/compose.yaml config --services
            fi
        fi
        run docker image ls
        pause
        title '6. Работа контейнеров и приложения testapp'
        run docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
        http http://127.0.0.1:8080/
        pause
        ;;
    '2 hq-cli')
        title '1. Членство в домене и разрешённые команды sudo'
        run system-auth status
        run id hquser1
        run cat /etc/sudoers.d/hq
        pause
        title '3. Автомонтирование NFS'
        run grep -E '[[:space:]]/mnt/nfs[[:space:]]' /etc/fstab
        run timeout 15 ls -ld /mnt/nfs/.
        run findmnt -T /mnt/nfs
        pause
        title '3. Запись и чтение временного файла через NFS'
        run timeout 20 bash -c '
            case $(findmnt -n -o FSTYPE -T /mnt/nfs) in
                nfs|nfs4) ;;
                *) echo "NFS не смонтирован в /mnt/nfs"; exit 1 ;;
            esac
            file=$(mktemp /mnt/nfs/practice-check.XXXXXX) || exit
            trap '\''rm -f -- "$file"'\'' EXIT
            printf "NFS write OK\n" > "$file" && cat "$file"
        '
        pause
        chrony_client
        title '9. Версия пакета Яндекс Браузера'
        run bash -c 'rpm -qa | grep -Ei "yandex.*browser|browser.*yandex"'
        printf 'Открой браузер из меню и сними окно с версией.\n'
        pause
        ;;
    '2 hq-cli-user')
        title '1. Вход и проверка прав доменного пользователя'
        run whoami
        run id
        run sudo -n -l
        run sudo -n cat /etc/hostname
        run sudo -n grep '^root:' /etc/passwd
        run sudo -n id
        printf '\nДля следующей команды ожидается отказ.\n'
        run sudo -n ls /root
        pause
        ;;
esac

printf '\nГотово. Проверки для %s (%s) закончены.\n' "$role" "$host_name"
