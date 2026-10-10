#!/bin/bash
# Подключение к LG webOS TV по SSH без ручного ввода пароля.
# ponytail: sshpass не установлен, используем штатный SSH_ASKPASS вместо установки пакета.
# Использование:  TV_IP=<IP ТВ> TV_PASS=<пароль root> ./tv-ssh.sh ['команда']
set -euo pipefail

TV_IP="${TV_IP:?нужен IP ТВ в TV_IP}"
TV_USER="${TV_USER:-root}"
TV_PASS="${TV_PASS:?нужен пароль SSH ТВ в TV_PASS}"

ASKPASS="$(mktemp)"
trap 'rm -f "$ASKPASS"' EXIT
printf '#!/bin/sh\nprintf "%%s\\n" %q\n' "$TV_PASS" > "$ASKPASS"
chmod 700 "$ASKPASS"

# ponytail: ключ хоста не проверяется (ТВ в домашней сети); подменивший ТВ в той же сети получит пароль
SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
setsid -w ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password \
  -o NumberOfPasswordPrompts=1 \
  -o ConnectTimeout=8 \
  -o LogLevel=ERROR \
  "${TV_USER}@${TV_IP}" "$@"
