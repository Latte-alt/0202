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
account=$(id -un)
prompt_sign='$'
if (( EUID == 0 )); then prompt_sign='#'; fi
trap 'exit 130' INT

prompt() {
    local directory=${PWD##*/}
    if [[ $PWD == "${HOME:-}" ]]; then directory='~'; fi
    printf '[%s@%s %s]%s ' "$account" "${host_name%%.*}" "${directory:-/}" "$prompt_sign"
}

pause() {
    local answer
    prompt
    IFS= read -rs answer <&3 || exit 0
    printf '\n'
    case "$answer" in q|Q) exit 0 ;; esac
}

new_frame() {
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then printf '\033[2J\033[H'; fi
}

run() {
    local arg
    prompt
    if [[ $# == 3 && $1 == bash && $2 == -c ]]; then
        printf '%s\n' "$3"
    else
        printf '%q' "$1"
        for arg in "${@:2}"; do printf ' %q' "$arg"; done
        printf '\n'
    fi
    "$@" <&3
}

http() {
    run curl -sS -o /dev/null -w 'HTTP %{http_code}\n' "$1"
}

ssh_check() {
    run ssh -p 2027 "sshuser@$1" "$2"
}

chrony_client() {
    new_frame
    run chronyc -n sources -v
    run chronyc tracking
    pause
}

if [[ $task == 1 ]]; then
    new_frame
    run hostname
    run ip -br -4 addr
    run ip -4 route
    run timedatectl show -p Timezone
    pause
fi

case "$task $role" in
    '1 isp')
        new_frame
        run iptables -t nat -S
        run sysctl net.ipv4.ip_forward
        pause
        ;;
    '1 br-fw')
        new_frame
        run vtysh -c 'show ip ospf neighbor'
        run vtysh -c 'show ip ospf interface'
        pause
        new_frame
        run vtysh -c 'show ip route ospf'
        pause
        ;;
    '1 hq-srv'|'1 br-srv')
        new_frame
        run id sshuser
        run bash -c 'sshd -T | grep -E "^(port|allowusers|maxauthtries|banner) "'
        run bash -c 'banner=$(sshd -T | awk '\''$1 == "banner" {print $2; exit}'\''); if [[ $banner == /* ]]; then cat -- "$banner"; fi'
        pause
        if [[ $role == hq-srv ]]; then
            new_frame
            for name in hq-rtr br-rtr br-fw hq-srv hq-cli br-srv docker web; do
                run host -t A "$name.au-team.irpo" 127.0.0.1
            done
            pause
            new_frame
            run host "$hq_srv" 127.0.0.1
            run host "$br_srv" 127.0.0.1
            run host ya.ru 127.0.0.1
            pause
        else
            new_frame
            run ping -c 3 "$hq_srv"
            run ping -c 3 77.88.8.8
            pause
        fi
        ;;
    '1 hq-cli')
        new_frame
        if command -v nmcli >/dev/null; then
            run nmcli -f GENERAL.DEVICE,IP4,DHCP4 device show
        else
            run ip -4 addr
        fi
        run cat /etc/resolv.conf
        pause
        new_frame
        run ping -c 3 "$br_srv"
        run ping -c 3 77.88.8.8
        pause
        new_frame
        ssh_check "$hq_srv" 'hostname; id; sudo -n id'
        pause
        new_frame
        ssh_check "$br_srv" 'hostname; id; sudo -n id'
        pause
        ;;
    '2 isp')
        new_frame
        run systemctl is-active chronyd
        run grep -E '^[[:space:]]*(pool|server|local|allow)[[:space:]]' /etc/chrony.conf
        run chronyc -n sources
        run chronyc tracking
        pause
        new_frame
        http "http://$hq_wan:8080/"
        ssh_check "$hq_wan" 'hostname; id'
        pause
        new_frame
        http "http://$br_wan:8080/"
        ssh_check "$br_wan" 'hostname; id'
        pause
        ;;
    '2 hq-srv')
        new_frame
        run lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
        run cat /proc/mdstat
        run mdadm --detail /dev/md0
        pause
        new_frame
        run grep -E '^[[:space:]]*ARRAY' /etc/mdadm.conf
        run grep /raid /etc/fstab
        run findmnt /raid
        pause
        new_frame
        run cat /etc/exports
        run exportfs -v
        pause
        chrony_client
        new_frame
        run bash -c 'systemctl is-active httpd2 || systemctl is-active apache2'
        run bash -c 'systemctl is-active mariadb || systemctl is-active mysqld'
        run ls -l /var/www/html/index.php /var/www/html/logo.png
        http http://127.0.0.1/
        pause
        new_frame
        run mysql -u web -p -D webdb -e 'SELECT CURRENT_USER(), DATABASE(); SHOW TABLES;'
        pause
        ;;
    '2 br-srv')
        new_frame
        run samba-tool computer list
        run bash -c 'samba-tool user list | sort | grep -E "^hquser[1-5]$"'
        run samba-tool group listmembers hq
        pause
        new_frame
        run samba-tool domain passwordsettings show
        pause
        chrony_client
        new_frame
        if cd /etc/ansible; then
            run pwd
            run ansible-inventory --graph
        fi
        pause
        new_frame
        if [[ $PWD == /etc/ansible ]]; then
            run ansible all -m ping
        fi
        pause
        new_frame
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
        new_frame
        run docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
        http http://127.0.0.1:8080/
        pause
        ;;
    '2 hq-cli')
        new_frame
        run system-auth status
        run id hquser1
        run cat /etc/sudoers.d/hq
        pause
        new_frame
        run grep /mnt/nfs /etc/fstab
        run ls -ld /mnt/nfs/.
        run findmnt /mnt/nfs
        pause
        new_frame
        case $(findmnt -n -o FSTYPE /mnt/nfs) in
            nfs|nfs4)
                run bash -c 'file=$(mktemp /mnt/nfs/check.XXXXXX) || exit
trap '\''rm -f "$file"'\'' EXIT
echo "NFS write OK" > "$file" && cat "$file"'
                ;;
            *) printf 'NFS не смонтирован в /mnt/nfs.\n' ;;
        esac
        pause
        chrony_client
        new_frame
        run bash -c 'rpm -qa | grep -Ei "yandex.*browser|browser.*yandex"'
        pause
        printf 'Открой браузер из меню и сними окно с версией.\n'
        ;;
    '2 hq-cli-user')
        new_frame
        run whoami
        run id
        run sudo -n -l
        run sudo -n cat /etc/hostname
        run sudo -n grep '^root:' /etc/passwd
        run sudo -n id
        run sudo -n ls /root
        pause
        ;;
esac

printf '\nГотово. Проверки для %s (%s) закончены.\n' "$role" "$host_name"
