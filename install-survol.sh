#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -f qml/Main.qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-survol-menu main
git rm -q --ignore-unmatch install-*.sh || true

python3 <<'PY'
def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

mq = 'qml/Main.qml'
edit(mq, '''                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: menuArea.containsMouse ? "#E6F6F4" : "transparent"
                            }

''', '')
edit(mq, '''                                        color: "#0B7F74"''', '''                                        color: menuArea.containsMouse ? "#0F9D8F" : "#0B7F74"''')
print("survol corrigé")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "design: suppression du fond vert au survol de l'icône de menu (seules les barres changent de couleur)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-survol-menu."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-survol-menu"
