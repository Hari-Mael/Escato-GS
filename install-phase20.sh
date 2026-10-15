#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ] || [ ! -f assets/logo.png ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS (assets/logo.png doit exister)"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-design-logo main
git rm -q --ignore-unmatch install-phase*.sh || true

if ! grep -q "hScroll" qml/Main.qml; then
    echo "Erreur : applique d'abord la phase 19 (adaptation à l'écran), puis relance ce script."
    exit 1
fi

python3 <<'PY'
def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

sb = 'qml/components/Sidebar.qml'
edit(sb, '''        Label {
            text: "ESCATO GS"
            color: "white"
            font.pixelSize: 22
            font.bold: true
            Layout.bottomMargin: 10
        }
''', '''        Image {
            id: logo
            source: "qrc:/assets/logo.png"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 120
            Layout.preferredWidth: 100
            Layout.bottomMargin: 10
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
''')

mq = 'qml/Main.qml'
edit(mq, '''                        AppButton {
                            text: "☰"
                            font.pixelSize: 18
                            implicitWidth: 44
                            onClicked: win.sidebarOpen = !win.sidebarOpen
                        }
''', '''                        Item {
                            implicitWidth: 40
                            implicitHeight: 40

                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: menuArea.containsMouse ? "#E6F6F4" : "transparent"
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 5
                                Repeater {
                                    model: 3
                                    Rectangle {
                                        width: 18
                                        height: 2
                                        radius: 1
                                        color: "#0B7F74"
                                    }
                                }
                            }

                            MouseArea {
                                id: menuArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.sidebarOpen = !win.sidebarOpen
                            }
                        }
''')

cm = 'CMakeLists.txt'
s = open(cm, encoding='utf-8').read()
s = s.rstrip('\n') + '\n\nqt_add_resources(escato_app escato_assets PREFIX "/" FILES assets/logo.png)\n'
open(cm, 'w', encoding='utf-8').write(s)
print("phase 20 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "design: logo ESCATO dans le menu latéral, icône de menu plus fine, logo intégré aux ressources"

echo ""
echo "Commit créé sur la branche feat/escato-gs-design-logo."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-design-logo"
