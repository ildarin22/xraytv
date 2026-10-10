#!/bin/bash
# Установка приложения Xray на ТВ с ПК (пароль root по SSH — в TV_PASS):
#   ./install.sh <IP ТВ> [<ссылка на подписку>]   поставить/обновить; со ссылкой — ещё и настроить
#   ./install.sh --remove <IP ТВ>                  удалить: Xray, автозапуск, ключ, пакет
set -euo pipefail
cd "$(dirname "$0")"
SSH=$PWD/tv-ssh.sh
APP=/media/developer/apps/usr/palm/applications/xraytv.app

# Вызов appInstallService и ожидание состояния $3. «luna-send -n 1» под root-ssh молча
# ничего не делает, поэтому -i в фоне с чтением ответов из файла.
luna_wait() {  # метод, параметры JSON, состояние успеха
  "$SSH" "L=/tmp/xraytv-luna.log
luna-send -i -f luna://com.webos.appInstallService/$1 '$2' > \$L 2>&1 &
P=\$!; i=0
while [ \$i -lt 120 ] && ! grep -qE '\"$3\"|fail' \$L; do sleep 1; i=\$((i + 1)); done
kill \$P 2>/dev/null
grep -q '\"$3\"' \$L || { cat \$L; exit 1; }"
}

install_ipk() {
  local ipk; ipk=$(ls -t dist/xraytv.app_*_arm.ipk | head -n 1)
  echo "ставлю $ipk"
  "$SSH" 'cat > /tmp/xraytv.ipk' < "$ipk"
  luna_wait dev/install '{"id":"xraytv.app","ipkUrl":"/tmp/xraytv.ipk","subscribe":true}' installed
  "$SSH" 'rm -f /tmp/xraytv.ipk'
  echo "пакет установлен"
}

case "${1:-}" in
  "" | -h | --help) sed -n '2,4p' "$0"; exit 1 ;;
  --remove)
    export TV_IP=${2:?нужен IP ТВ}
    "$SSH" "sh $APP/xrayctl remove" || true   # пакета уже может не быть
    luna_wait dev/remove '{"id":"xraytv.app","subscribe":true}' removed
    echo "пакет удалён"
    exit ;;
esac
export TV_IP=$1
install_ipk
if [ -n "${2:-}" ]; then
  # ссылка идёт через stdin: не попадает в кавычки ssh и в список процессов ТВ
  printf '%s\n' "$2" | "$SSH" "sh $APP/xrayctl setup -"
else
  "$SSH" "sh $APP/xrayctl reload"   # новый бинарник/шаблон, если ключ есть и Xray не выключен
fi
"$SSH" "sh $APP/xrayctl status"
