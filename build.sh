#!/bin/bash
# Сборка ipk приложения Xray для webOS. Нужны: curl, sha256sum, python3, tar.
#   ./build.sh   → печатает путь к dist/xraytv.app_<версия>_arm.ipk, рядом манифест для каталога
set -euo pipefail
cd "$(dirname "$0")"
VER=26.9.30
declare -A SHA=(
  [Xray-linux-arm32-v7a]=0b9719471c7c69752857714e9711d4da57cf38a6beb75dcddfb21425f7919908
  [Xray-linux-64]=f851110beaff16e78d643f0ccfd9524b4a44dfd59bae3e34bb52bba378f7690e
)
fetch() {  # $1 — имя архива релиза; результат: .cache/$1/xray
  local d=.cache/$1
  [ -x "$d/xray" ] && return
  mkdir -p "$d"
  curl -fsSL -o "$d/x.zip" "https://github.com/XTLS/Xray-core/releases/download/v$VER/$1.zip"
  echo "${SHA[$1]}  $d/x.zip" | sha256sum -c --quiet -
  python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extract("xray", sys.argv[2])' "$d/x.zip" "$d"
  chmod 755 "$d/xray"; rm -f "$d/x.zip"
}
fetch Xray-linux-64          # для тестов на ПК (xray run -test)
fetch Xray-linux-arm32-v7a   # в пакет для ТВ

APPVER=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' app/appinfo.json)
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
D=$B/data/usr/palm/applications/xraytv.app
mkdir -p "$D" "$B/control" dist
cp app/* "$D/"
cp .cache/Xray-linux-arm32-v7a/xray "$D/xray"
chmod 755 "$D/xray" "$D/autostart.sh"
cat > "$B/control/control" <<EOF
Package: xraytv.app
Version: $APPVER
Section: misc
Priority: optional
Architecture: all
Installed-Size: $(du -sk "$B/data" | cut -f1)
Maintainer: home
Description: Xray for YouTube
webOS-Package-Format-Version: 2
webOS-Packager-Version: x.y.x
EOF
echo 2.0 > "$B/debian-binary"
tar -C "$B/control" --owner=0 --group=0 -czf "$B/control.tar.gz" .
tar -C "$B/data" --owner=0 --group=0 -czf "$B/data.tar.gz" .
OUT=$PWD/dist/xraytv.app_${APPVER}_arm.ipk
rm -f "$OUT"
# ar пишем сами: GNU ar ставит «/» после имён, и установщик webOS отвечает «Failed to extract package»
python3 -I - "$OUT" "$B" app/appinfo.json <<'EOF'
import hashlib, json, os, sys, time
out, d, info = sys.argv[1], sys.argv[2], json.load(open(sys.argv[3]))
with open(out, 'wb') as f:
    f.write(b'!<arch>\n')
    for n in ('debian-binary', 'control.tar.gz', 'data.tar.gz'):
        b = open(os.path.join(d, n), 'rb').read()
        f.write(('%-16s%-12d%-6d%-6d%-8s%-10d`\n' % (n, int(time.time()), 0, 0, '100644', len(b))).encode())
        f.write(b + b'\n' * (len(b) % 2))
# манифест для каталога Homebrew Channel: ipkUrl относительно самого манифеста
ipk = open(out, 'rb').read()
m = dict({k: info[k] for k in ('id', 'version', 'type', 'title')}, ipkUrl=os.path.basename(out),
         ipkHash={'sha256': hashlib.sha256(ipk).hexdigest()}, ipkSize=len(ipk))
with open(os.path.join(os.path.dirname(out), info['id'] + '.manifest.json'), 'w') as f:
    f.write(json.dumps(m, indent=2) + '\n')
EOF
echo "$OUT"
