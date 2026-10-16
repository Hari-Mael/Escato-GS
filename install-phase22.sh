#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -f qml/components/Sidebar.qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi
if [ ! -f assets/fonts/MaterialSymbolsRounded.ttf ]; then
    echo "Erreur : place d'abord la police dans assets/fonts/MaterialSymbolsRounded.ttf (puis commit)."
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-icones main
git rm -q --ignore-unmatch install-*.sh || true

if [ ! -f assets/fonts/LICENSE-MaterialSymbols.txt ]; then
    curl -fsSL -o assets/fonts/LICENSE-MaterialSymbols.txt \
        "https://raw.githubusercontent.com/google/material-design-icons/master/LICENSE" \
        || { echo "Erreur : téléchargement de la licence impossible"; exit 1; }
fi

cat > qml/components/Icon.qml <<'QML'
import QtQuick

Text {
    id: root
    property string name: ""
    property int size: 20

    text: name
    font.family: "Material Symbols Rounded"
    font.pixelSize: size
    color: "#0B7F74"
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
QML

python3 <<'PY'
import re

def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

ICONS = {
    "dashboard": "dashboard", "students": "school", "teachers": "person_book", "courses": "menu_book",
    "exams": "edit_note", "curriculum": "calendar_month", "attendance": "fact_check", "discipline": "gavel",
    "council": "workspace_premium", "administration": "account_balance", "finreports": "bar_chart",
    "treasury": "account_balance_wallet", "finextra": "request_quote", "import": "upload_file", "email": "mail",
    "hr": "groups", "finance": "payments", "accounting": "receipt_long", "communication": "campaign",
    "accounts": "lock", "bulletin": "description", "audit": "history", "fees": "sell", "roles": "admin_panel_settings",
}

sb = 'qml/components/Sidebar.qml'
s = open(sb, encoding='utf-8').read()
missing = []
def repl_model(m):
    key, label = m.group(1), m.group(2)
    if key not in ICONS:
        missing.append(key)
        return m.group(0)
    return '["%s", "%s", "%s"]' % (key, label, ICONS[key])
s, n = re.subn(r'\["(\w+)", "([^"]+)"\]', repl_model, s)
assert not missing, missing
assert n == len(ICONS), (n, len(ICONS))

s, n = re.subn(r'Text \{\n\s*anchors\.centerIn: parent\n\s*text: root\.initials\(entry\.modelData\[1\]\)\n\s*color: "white"\n\s*font\.pixelSize: 10\n\s*font\.bold: true\n\s*\}',
               'Text {\n                                    anchors.centerIn: parent\n                                    text: entry.modelData[2]\n                                    color: "white"\n                                    font.family: "Material Symbols Rounded"\n                                    font.pixelSize: 17\n                                }', s)
assert n == 1, n
s, n = re.subn(r'text: "⚙"\n(\s*)color: "#C9DCEB"\n\s*font\.pixelSize: 18',
               lambda m: 'text: "settings"\n%scolor: "#C9DCEB"\n%sfont.family: "Material Symbols Rounded"\n%sfont.pixelSize: 22' % (m.group(1), m.group(1), m.group(1)), s)
assert n == 1, n
s, n = re.subn(r'text: "⏻"\n(\s*)color: logoutArea\.containsMouse \? "#FFB4B4" : "#C9DCEB"\n\s*font\.pixelSize: 17',
               lambda m: 'text: "logout"\n%scolor: logoutArea.containsMouse ? "#FFB4B4" : "#C9DCEB"\n%sfont.family: "Material Symbols Rounded"\n%sfont.pixelSize: 20' % (m.group(1), m.group(1), m.group(1)), s)
assert n == 1, n
open(sb, 'w', encoding='utf-8').write(s)

mq = 'qml/Main.qml'
s = open(mq, encoding='utf-8').read()
start_marker = '                        Item {\n                            implicitWidth: 40\n'
end_marker = '                                onClicked: win.sidebarOpen = !win.sidebarOpen\n                            }\n                        }\n'
a = s.index(start_marker)
b = s.index(end_marker, a) + len(end_marker)
new_block = ('                        Item {\n'
             '                            implicitWidth: 40\n'
             '                            implicitHeight: 40\n\n'
             '                            Icon {\n'
             '                                anchors.centerIn: parent\n'
             '                                name: "menu"\n'
             '                                size: 24\n'
             '                                color: menuArea.containsMouse ? "#0F9D8F" : "#0B7F74"\n'
             '                            }\n\n'
             '                            MouseArea {\n'
             '                                id: menuArea\n'
             '                                anchors.fill: parent\n'
             '                                hoverEnabled: true\n'
             '                                cursorShape: Qt.PointingHandCursor\n'
             '                                onClicked: win.sidebarOpen = !win.sidebarOpen\n'
             '                            }\n'
             '                        }\n')
s = s[:a] + new_block + s[b:]
open(mq, 'w', encoding='utf-8').write(s)
edit(mq, '    color: "#F4F7FA"\n', '    color: "#F4F7FA"\n\n    FontLoader {\n        id: iconFont\n        source: "qrc:/assets/fonts/MaterialSymbolsRounded.ttf"\n    }\n')

cm = 'CMakeLists.txt'
edit(cm, 'qt_add_resources(escato_app escato_assets PREFIX "/" FILES assets/logo.png)',
     'qt_add_resources(escato_app escato_assets PREFIX "/" FILES assets/logo.png assets/fonts/MaterialSymbolsRounded.ttf)')
edit(cm, '        qml/components/Sidebar.qml\n', '        qml/components/Sidebar.qml\n        qml/components/Icon.qml\n')
print("phase 22 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "design: icônes Material Symbols Rounded (menu, bouton ☰, paramètres, déconnexion), police intégrée aux ressources"

echo ""
echo "Commit créé sur la branche feat/escato-gs-icones."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-icones"
