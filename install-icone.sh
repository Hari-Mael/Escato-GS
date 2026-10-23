#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d installer ] || [ ! -f assets/nouveau-logo.png ]; then
    echo "Erreur : lance ce script à la racine du dépôt, après avoir placé le logo dans assets/nouveau-logo.png"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-icone-application main
git rm -q --ignore-unmatch install-*.sh || true

if ! python3 -c "import PIL" 2>/dev/null; then
    pip install --user -q pillow
fi

python3 <<'PY'
import re
from PIL import Image, ImageDraw

src = Image.open('assets/nouveau-logo.png').convert('RGBA')
w, h = src.size
for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
    ImageDraw.floodfill(src, seed, (0, 0, 0, 0), thresh=60)
side = max(w, h)
canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
canvas.paste(src, ((side - w) // 2, (side - h) // 2), src)
icon = canvas.resize((256, 256), Image.LANCZOS)
icon.save('assets/logo.png')
icon.save('assets/app.ico', format='ICO', sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])
print("logo et icône générés")

open('src/app.rc', 'w', encoding='utf-8').write('IDI_ICON1 ICON "../assets/app.ico"\n')

cm = 'CMakeLists.txt'
s = open(cm, encoding='utf-8').read()
if 'src/app.rc' not in s:
    s = s.rstrip('\n') + '\n\nif(WIN32)\n    target_sources(escato_app PRIVATE src/app.rc)\nendif()\n'
    open(cm, 'w', encoding='utf-8').write(s)

for iss in ['installer/escato.iss', 'installer/escato-online.iss']:
    t = open(iss, encoding='utf-8').read()
    if 'SetupIconFile' not in t:
        t, n = re.subn(r'(OutputBaseFilename=[^\n]*\n)', r'\1SetupIconFile=..\\assets\\app.ico\n', t, count=1)
        assert n == 1, iss
        open(iss, 'w', encoding='utf-8').write(t)
print("installateurs mis à jour")
PY

git rm -q --cached assets/nouveau-logo.png 2>/dev/null || true
rm -f assets/nouveau-logo.png

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: nouveau logo ESCATO (menu, icône de l'exécutable, icône de l'installateur et des raccourcis)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-icone-application."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-icone-application"
