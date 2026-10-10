#!/bin/bash
# Выпуск версии из app/appinfo.json:  ./release.sh   (нужны gh после «gh auth login» и закоммиченный main)
# ipk уходит в релиз GitHub v<версия>, манифест с полным адресом ipk — в main рядом с repo.json:
# Homebrew Channel читает каталог и манифест из браузера, а у файлов релизов нет CORS, у raw-адресов есть.
set -euo pipefail
cd "$(dirname "$0")"
M=xraytv.app.manifest.json
V=$(python3 -I -c 'import json; print(json.load(open("app/appinfo.json"))["version"])')
DIRTY=$(git status --porcelain)
[ -z "$DIRTY" ] || { echo "ошибка: есть незакоммиченные изменения" >&2; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo "ошибка: выпуск только из main" >&2; exit 1; }
! gh release view "v$V" > /dev/null 2>&1 || { echo "ошибка: v$V уже выпущена, поднимите версию в app/appinfo.json" >&2; exit 1; }
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
git push -q
IPK=$(./build.sh)
node test/build.test.js
gh release create "v$V" "$IPK" --target "$(git rev-parse HEAD)" --title "v$V" --notes "Xray для ТВ $V"
# ponytail: релиз и манифест в main — два шага; упадёт второй — каталог останется на прошлой версии
trap 'echo "релиз v$V создан, но манифест не в main: закоммитьте $M и git push (пересборка даст другой хэш)" >&2' ERR
python3 -I - "dist/$M" "https://github.com/$REPO/releases/download/v$V/" "$M" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
m['ipkUrl'] = sys.argv[2] + m['ipkUrl']
open(sys.argv[3], 'w').write(json.dumps(m, indent=2) + '\n')
PY
git add "$M"
git commit -qm "выпуск $V"
git push -q
echo "выпущено $V: https://github.com/$REPO/releases/tag/v$V"
