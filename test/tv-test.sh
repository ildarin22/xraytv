#!/bin/bash
# Сценарии xrayctl на ТВ, запускаются с ПК:
#   TV_IP=<IP ТВ> TV_PASS=<пароль root> XRAYTV_SUB=<подписка> test/tv-test.sh [группа ...]
# Заливает скрипты из app/ в установленный пакет, останавливает ЛЮБОЙ Xray на ТВ
# (YouTube на это время без прокси), в конце возвращает рабочий Xray.
set -uo pipefail
cd "$(dirname "$0")"
T=$PWD/../tv-ssh.sh
: "${XRAYTV_SUB:?нужна подписка в XRAYTV_SUB}" "${TV_IP:?нужен TV_IP}" "${TV_PASS:?нужен TV_PASS}"
APP=/media/developer/apps/usr/palm/applications/xraytv.app
CTL=$APP/xrayctl
DATA=/media/developer/xraytv
HOOK=/var/lib/webosbrew/init.d/70-xraytv
fail=0

check() {  # описание, ожидаемое (grep -E по выводу), команда на ТВ
  local out; out=$("$T" "$3" 2>&1)
  if printf '%s\n' "$out" | grep -qE -- "$2"; then echo "ok   $1"
  else echo "FAIL $1"; echo "     ждали: $2"; printf '%s\n' "$out" | head -n 5 | sed 's/^/     было: /'; fail=1; fi
}

check_json() {  # описание, JS-условие над s, команда на ТВ (последняя строка вывода — JSON)
  local out; out=$("$T" "$3" 2>&1)
  if printf '%s\n' "$out" | tail -n 1 | node -e "const s = JSON.parse(require('fs').readFileSync(0, 'utf8')); process.exit(($2) ? 0 : 1)" 2>/dev/null
  then echo "ok   $1"
  else echo "FAIL $1"; printf '%s\n' "$out" | tail -n 3 | sed 's/^/     было: /'; fail=1; fi
}

prepare() {
  for f in xrayctl mkconfig.js config.template.json autostart.sh; do "$T" "cat > $APP/$f" < "../app/$f"; done
  "$T" 'killall xray 2>/dev/null; i=0; while pidof xray >/dev/null && [ $i -lt 10 ]; do sleep 1; i=$((i + 1)); done'
  # подписка из XRAYTV_SUB, нигде не печатается
  printf '%s\n' "$XRAYTV_SUB" |
    "$T" "mkdir -p $DATA && umask 077 && cat > $DATA/subscription.url"
  # ключ для сценариев (то же, что делает update-key, но без него)
  "$T" "APP=$APP DATA=$DATA sh -s" <<'EOF'
H=$(sed -n 's#^[a-z]*://\([^/:?]*\).*#\1#p' "$DATA/subscription.url")
mkdir -p /tmp/xraytv
curl -fsS -m 15 -o /tmp/xraytv/sub.txt "$(cat "$DATA/subscription.url")" &&
  node "$APP/mkconfig.js" parse /tmp/xraytv/sub.txt "$H" "$(node "$APP/mkconfig.js" resolve "$H")" > "$DATA/key.json" &&
  echo "prepare: ключ готов"
EOF
}

restore() {
  "$T" "sh $CTL stop >/dev/null 2>&1
if [ -x /media/developer/xray/xray ]; then cd /media/developer/xray && DELAY=0 sh startup.sh; else sh $CTL start >/dev/null; fi
sleep 4; pidof xray >/dev/null && echo 'restore: Xray работает' || echo 'restore: Xray НЕ работает'"
}

t_core() {
  check "iface: Wi-Fi → wlan0" '^wlan0$' "printf 'default via 192.168.1.1 dev wlan0  proto dhcp\n192.168.1.0/24 dev wlan0\n' | sh $CTL _iface"
  check "iface: кабель → eth0" '^eth0$' "ip route | sh $CTL _iface"
  check "start запускает" 'Xray включён' "sh $CTL start"
  check "маршрут на xray0" '0\.0\.0\.0/1 dev xray0' "ip route"
  check "интерфейс в конфиге" '"autoOutboundsInterface": "eth0"' "cat /tmp/xraytv/config.json"
  check "YouTube отвечает" '^[23][0-9][0-9]$' "curl -s -o /dev/null -m 10 -w '%{http_code}' https://www.youtube.com/generate_204"
  check "повторный start — один процесс" '^ *1$' "sh $CTL start >/dev/null; pidof xray | wc -w"
  check "boot при работающем — один процесс" '^ *1$' "DELAY=1 sh $CTL boot; sleep 6; pidof xray | wc -w"
  check "stop останавливает" 'Xray выключен' "sh $CTL stop"
  check "после stop нет маршрутов xray0" '^0$' "ip route | grep -c xray0"
  check "после stop default на месте" 'default via 192\.168\.0\.1 dev eth0' "ip route"
  check "boot при DISABLE не запускает" '^ *0$' "DELAY=1 sh $CTL boot; sleep 6; pidof xray | wc -w"
  check "reload при DISABLE не запускает" '^ *0$' "sh $CTL reload; pidof xray | wc -w"
  check "boot без DISABLE запускает" '^ *1$' "rm -f $DATA/DISABLE; DELAY=1 sh $CTL boot; sleep 8; pidof xray | wc -w"
  check "reload меняет процесс" '^changed$' "A=\$(pidof xray); sh $CTL reload; B=\$(pidof xray); [ -n \"\$B\" ] && [ \"\$A\" != \"\$B\" ] && echo changed"
  check "start без ключа — понятная ошибка" 'ошибка: ключ не настроен' "sh $CTL stop >/dev/null; mv $DATA/key.json /tmp/xraytv/k; sh $CTL start; mv /tmp/xraytv/k $DATA/key.json"
}

t_key() {
  "$T" "sh $CTL start >/dev/null"
  local K1; K1=$("$T" "md5sum < $DATA/key.json" | cut -d' ' -f1)
  check "update-key: не изменился" 'ключ не изменился' "sh $CTL update-key"
  check "update-key: подписка недоступна" 'ошибка: подписка недоступна' "cp $DATA/subscription.url /tmp/xraytv/u; echo http://127.0.0.1:9/sub > $DATA/subscription.url; sh $CTL update-key 2>&1; cp /tmp/xraytv/u $DATA/subscription.url"
  check "update-key: мусор вместо подписки" 'ошибка: в подписке нет ссылки vless' "echo hello > /tmp/xraytv/g.txt; cp $DATA/subscription.url /tmp/xraytv/u; echo file:///tmp/xraytv/g.txt > $DATA/subscription.url; sh $CTL update-key 2>&1; cp /tmp/xraytv/u $DATA/subscription.url"
  check "update-key: плохой ключ отсекает xray -test" 'ошибка: новый ключ не прошёл проверку' "printf '%s' 'vless://11111111-2222-3333-4444-555555555555@203.0.113.7:443?type=tcp&security=reality&pbk=bad&sni=www.example.com&sid=ab12' | base64 > /tmp/xraytv/bad.txt; cp $DATA/subscription.url /tmp/xraytv/u; echo file:///tmp/xraytv/bad.txt > $DATA/subscription.url; sh $CTL update-key 2>&1; cp /tmp/xraytv/u $DATA/subscription.url"
  check "после ошибок key.json прежний" "^$K1" "md5sum < $DATA/key.json"
  check "итог ошибки записан в update.log" 'ошибка' "cat $DATA/update.log"
  # Review Focus 1: IP сервера заблокирован → «Обновить ключ» чинит
  check "мёртвый прокси: YouTube не отвечает" '^000$' "cp $DATA/key.json /tmp/xraytv/good.json; sed 's/\"address\": *\"[^\"]*\"/\"address\": \"203.0.113.1\"/' /tmp/xraytv/good.json > $DATA/key.json; sh $CTL reload; curl -s -o /dev/null -m 8 -w '%{http_code}' https://www.youtube.com/generate_204"
  check "мёртвый прокси: update-key обновляет" 'ключ обновлён' "sh $CTL update-key"
  check "после update-key YouTube работает" '^[23][0-9][0-9]$' "sleep 2; curl -s -o /dev/null -m 10 -w '%{http_code}' https://www.youtube.com/generate_204"
  check "мёртвый ключ сохранён в key.prev.json" '203\.0\.113\.1' "cat $DATA/key.prev.json"
  # подписка раздаёт случайный sid из списка сервера: другой sid — не новый ключ, пока прокси работает
  check "чужой sid при мёртвом прокси: update-key обновляет" 'ключ обновлён' "sed 's/\"sid\": *\"[^\"]*\"/\"sid\": \"0bad\"/' $DATA/key.json > /tmp/xraytv/k.json; cp /tmp/xraytv/k.json $DATA/key.json; sh $CTL reload; sh $CTL update-key"
  check "только sid при мёртвом прокси: key.prev.json прежний" '^prev-kept$' "P=\$(md5sum < $DATA/key.prev.json); sed 's/\"sid\": *\"[^\"]*\"/\"sid\": \"0dead0\"/' $DATA/key.json > /tmp/xraytv/k.json; cp /tmp/xraytv/k.json $DATA/key.json; sh $CTL reload; sh $CTL update-key >/dev/null; [ \"\$(md5sum < $DATA/key.prev.json)\" = \"\$P\" ] && echo prev-kept"
  check "выключен: другой sid → не изменился" 'ключ не изменился' "sh $CTL stop >/dev/null; sh $CTL update-key; sh $CTL start >/dev/null"
  # экран шлёт подписку без перевода строки
  check "setup: подписка из stdin, запуск" 'Xray включён' "cp $DATA/subscription.url /tmp/xraytv/u; sh $CTL stop >/dev/null; printf '%s' \"\$(cat /tmp/xraytv/u)\" | sh $CTL setup -"
  check "setup: хук указывает на autostart.sh" "^$APP/autostart\.sh\$" "readlink $HOOK"
  check "setup: ссылка с правами 600" '^-rw-------' "ls -l $DATA/subscription.url"
  # неверная подписка в setup - не трогает подписку, ключ и предыдущий ключ
  local D; D=$("$T" "cat $DATA/subscription.url $DATA/key.json $DATA/key.prev.json | md5sum" | cut -d' ' -f1)
  check "setup: недоступная подписка — ошибка" 'ошибка: подписка недоступна.* rc=1 $' "{ echo http://127.0.0.1:9/sub | sh $CTL setup -; echo rc=\$?; } 2>&1 | tr '\n' ' '"
  check "setup: не-vless подписка — ошибка" 'ошибка: в подписке нет ссылки vless.* rc=1 $' "echo hello > /tmp/xraytv/g.txt; { echo file:///tmp/xraytv/g.txt | sh $CTL setup -; echo rc=\$?; } 2>&1 | tr '\n' ' '"
  check "setup с аргументом отвергается" 'setup -.* rc=1 $' "{ sh $CTL setup http://127.0.0.1:9/sub; echo rc=\$?; } 2>&1 | tr '\n' ' '"
  check "после ошибок setup подписка и ключи прежние" "^${D:-нет-md5}" "cat $DATA/subscription.url $DATA/key.json $DATA/key.prev.json | md5sum"
  check "после ошибок setup временной папки нет" '^clean$' "[ -e $DATA/.setup ] || echo clean"
  # devmode при каждой загрузке делает chmod -R 777 /media/developer
  check "boot закрывает папку данных (600/700)" '^0$' "chmod -R 777 $DATA; DELAY=1 sh $CTL boot; { ls -ld $DATA; ls -l $DATA/; } | grep -E '^[-d]' | grep -vcE '^(-rw-------|drwx------)'"
  # Review Focus 3: пакет удалён → висячий хук не мешает остальным хукам
  check "висячий хук не мешает другим хукам" '^ran$' "rm -rf /tmp/rp /tmp/rp-ok; mkdir /tmp/rp; ln -s /nonexistent/autostart.sh /tmp/rp/70-x; printf '#!/bin/sh\ntouch /tmp/rp-ok\n' > /tmp/rp/80-y; chmod +x /tmp/rp/80-y; run-parts /tmp/rp 2>/dev/null; [ -f /tmp/rp-ok ] && echo ran; rm -rf /tmp/rp /tmp/rp-ok"
  check "remove: Xray, хук и данные убраны" '^gone$' "cp $DATA/subscription.url /tmp/xraytv-u.keep; sh $CTL remove >/dev/null; [ ! -e $HOOK ] && [ ! -d $DATA ] && ! pidof xray >/dev/null && echo gone"
  check "setup после remove восстанавливает" 'Xray включён' "sh $CTL setup - < /tmp/xraytv-u.keep; rm -f /tmp/xraytv-u.keep"
  check_json "setup после remove: статус «работает»" 's.enabled && s.running && s.youtube.ok' "sh $CTL status"
  check "после setup данные и /tmp/xraytv закрыты (600/700)" '^0$' "{ ls -ld $DATA /tmp/xraytv; ls -l $DATA/ /tmp/xraytv/; } | grep -E '^[-d]' | grep -vcE '^(-rw-------|drwx------)'"
}

t_status() {
  "$T" "sh $CTL start >/dev/null"
  check_json "статус: всё работает" 's.enabled === true && s.running === true && s.iface === "eth0" && s.server.ok && s.server.ms > 0 && s.server.port === 443 && s.youtube.ok && s.youtube.ms > 0 && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(s.keyUpdated) && Array.isArray(s.errors)' "sh $CTL status"
  check_json "статус: интерфейс запущенного Xray" 's.xrayIface === "eth0"' "sh $CTL status"
  check_json "статус: свежий запуск без ошибок" 's.errors.length === 0' "sh $CTL reload; sh $CTL status"
  check_json "статус: кавычки, \\ и таб в логе не ломают JSON" 's.errors.some(function (e) { return e.indexOf("q\"x\\ytab") >= 0; })' "printf 'error: q\\042x\\134y\\011tab\\n' >> /tmp/xraytv/xray.log; sh $CTL status"
  check_json "статус: сервер недоступен" 's.server.ok === false' "cp $DATA/key.json /tmp/xraytv/good.json; sed 's/\"address\": *\"[^\"]*\"/\"address\": \"203.0.113.1\"/' /tmp/xraytv/good.json > $DATA/key.json; sh $CTL status; cp /tmp/xraytv/good.json $DATA/key.json"
  check_json "статус: выключен" 's.enabled === false && s.running === false && s.xrayIface === ""' "sh $CTL stop >/dev/null; sh $CTL status"
  check_json "статус: без ключа keyUpdated = null" 's.keyUpdated === null && s.server.host === ""' "mv $DATA/key.json /tmp/xraytv/k; sh $CTL status; mv /tmp/xraytv/k $DATA/key.json"
}

prepare
for g in ${@:-core key status}; do "t_$g"; done
restore
[ $fail = 0 ] && echo "ВСЕ ПРОВЕРКИ ПРОШЛИ" || { echo "ЕСТЬ ПРОВАЛЫ"; exit 1; }
