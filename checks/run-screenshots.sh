#!/usr/bin/env bash
# Run from the HQ-CLI terminal: bash run-screenshots.sh TASK [ROLE]
set -u

usage() {
    cat <<'EOF'
Запуск на HQ-CLI: bash run-screenshots.sh ЗАДАНИЕ [МАШИНА]
1: hq-cli hq-srv br-srv hq-rtr br-rtr isp br-fw
2: hq-cli hq-srv br-srv hq-rtr br-rtr isp hq-cli-user

Без имени машины запускаются все проверки выбранного задания.
Enter — начать машину, s — пропустить, q — выйти.
SSH-адреса можно переопределить через HQ_SRV_SSH, BR_SRV_SSH,
HQ_RTR_SSH, BR_RTR_SSH, ISP_SSH, BR_FW_SSH (в формате пользователь@адрес).
SSH-порты: HQ_SRV_PORT, BR_SRV_PORT, HQ_RTR_PORT, BR_RTR_PORT, ISP_PORT, BR_FW_PORT.
Адреса внутри проверок: HQ_SRV_IP, BR_SRV_IP, HQ_RTR_WAN, BR_RTR_WAN.
EOF
}

task=${1:-}
only=${2:-}
case "$task" in
    1) roles=(hq-cli hq-srv br-srv hq-rtr br-rtr isp br-fw) ;;
    2) roles=(hq-cli hq-srv br-srv hq-rtr br-rtr isp hq-cli-user) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
if (( $# > 2 )); then usage >&2; exit 2; fi
if [[ -n $only ]]; then
    if [[ " ${roles[*]} " != *" $only "* ]]; then usage >&2; exit 2; fi
    roles=("$only")
fi
if [[ ! -t 0 || ! -t 1 ]]; then
    printf 'Открой интерактивный терминал на HQ-CLI.\n' >&2
    exit 2
fi

# The two helpers are versioned together. Prefer the local copies in a checkout.
base=https://raw.githubusercontent.com/Latte-alt/0202/6c5819ab0ced33cccaa8db9054731d9bed67748c/checks
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -r $source_dir/linux-screenshots.sh && -r $source_dir/ecorouter-screenshots.py ]]; then
    helpers=$source_dir
else
    helpers=$(mktemp -d) || exit 1
    trap 'rm -f -- "$helpers/linux-screenshots.sh" "$helpers/ecorouter-screenshots.py"; rmdir -- "$helpers"' EXIT
    for file in linux-screenshots.sh ecorouter-screenshots.py; do
        curl -fsSL --connect-timeout 10 --max-time 30 "$base/$file" -o "$helpers/$file" || exit 1
    done
fi
trap 'exit 130' INT

hq_srv=${HQ_SRV_IP:-192.168.0.2}
br_srv=${BR_SRV_IP:-192.168.4.2}
hq_wan=${HQ_RTR_WAN:-172.16.1.2}
br_wan=${BR_RTR_WAN:-172.16.2.2}

# Quote arguments for the login shell, including the multi-line Bash source.
shell_args() {
    local arg
    for arg in "$@"; do printf "'%s' " "${arg//\'/\'\\\'\'}"; done
}

linux_command() {
    local role=$1 source=$2
    shell_args env "HQ_SRV_IP=$hq_srv" "BR_SRV_IP=$br_srv" "HQ_RTR_WAN=$hq_wan" "BR_RTR_WAN=$br_wan" \
        bash -c "$source" linux-screenshots.sh "$task" "$role"
}

linux_local() {
    local cmd
    cmd=$(linux_command "$1" "$(cat -- "$helpers/linux-screenshots.sh")")
    if [[ $1 == hq-cli-user ]]; then
        if (( EUID == 0 )); then
            printf 'Войди на этой же машине как hquser1 и запусти linux-screenshots.sh 2 hq-cli-user.\n'
            return 1
        fi
        if [[ ${USER:-} == hquser1 ]]; then bash -c "$cmd"; else su - hquser1 -c "$cmd"; fi
    elif (( EUID == 0 )); then
        bash -c "$cmd"
    elif command -v sudo >/dev/null && sudo -n true >/dev/null 2>&1; then
        sudo -n bash -c "$cmd"
    else
        printf 'Если появится запрос, введи пароль root для этой машины.\n'
        su - root -c "$cmd"
    fi
}

linux_remote() {
    local role=$1 target=$2 port=$3 cmd remote
    cmd=$(linux_command "$role" "$(cat -- "$helpers/linux-screenshots.sh")")
    remote="if [ \"\$(id -u)\" = 0 ]; then $cmd; elif command -v sudo >/dev/null && sudo -n true >/dev/null 2>&1; then $(shell_args sudo -n bash -c "$cmd"); else $(shell_args su - root -c "$cmd"); fi"
    printf 'SSH → %s:%s\n' "$target" "$port"
    ssh -tt -o ConnectTimeout=7 -o NumberOfPasswordPrompts=1 -p "$port" -- "$target" "$remote"
}

skipped=()
for role in "${roles[@]}"; do
    printf '\n── Задание %s | %s ──\n' "$task" "$role"
    if [[ -z $only ]]; then
        printf 'Enter — начать, s — пропустить машину, q — выйти: '
        IFS= read -r answer || exit 0
        case "$answer" in
            q|Q) exit 0 ;;
            s|S) skipped+=("$role"); continue ;;
        esac
    fi

    case "$role" in
        hq-cli|hq-cli-user) linux_local "$role" ;;
        hq-srv) linux_remote "$role" "${HQ_SRV_SSH:-sshuser@$hq_srv}" "${HQ_SRV_PORT:-2027}" ;;
        br-srv) linux_remote "$role" "${BR_SRV_SSH:-sshuser@$br_srv}" "${BR_SRV_PORT:-2027}" ;;
        isp) linux_remote "$role" "${ISP_SSH:-root@172.16.1.1}" "${ISP_PORT:-22}" ;;
        br-fw) linux_remote "$role" "${BR_FW_SSH:-root@192.168.4.1}" "${BR_FW_PORT:-22}" ;;
        hq-rtr) python3 "$helpers/ecorouter-screenshots.py" "$task" "$role" \
            "${HQ_RTR_SSH:-net_admin@192.168.1.1}" --port "${HQ_RTR_PORT:-22}" ;;
        br-rtr) python3 "$helpers/ecorouter-screenshots.py" "$task" "$role" \
            "${BR_RTR_SSH:-net_admin@192.168.3.1}" --port "${BR_RTR_PORT:-22}" ;;
    esac
    status=$?
    if (( status == 130 )); then exit 130; fi
    if (( status != 0 )); then
        printf 'Запуск на %s завершился с кодом %s. Проверь адрес и SSH или запусти помощник из консоли этой машины.\n' "$role" "$status" >&2
        skipped+=("$role")
    fi
done

if (( ${#skipped[@]} )); then
    printf '\nНужно доснять: %s\n' "${skipped[*]}"
    exit 1
fi
printf '\nОбход машин задания %s завершён.\n' "$task"
