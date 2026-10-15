#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-adaptation-ecran main
git rm -q --ignore-unmatch install-phase*.sh || true

cat > qml/components/Sidebar.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    color: "#092B45"
    clip: true
    property string currentPage: "dashboard"
    signal navigate(string page)

    property var perms: ({})
    function refreshPerms() {
        perms = {
            "audit": school.can("audit.view"),
            "fees": school.can("balances.view"),
            "roles": school.can("roles.manage")
        }
    }
    function pageAllowed(p) {
        return p in perms ? perms[p] : true
    }
    Component.onCompleted: refreshPerms()
    Connections {
        target: school
        function onDataChanged() { root.refreshPerms() }
        function onSessionChanged() { root.refreshPerms() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 6

        Label {
            text: "ESCATO GS"
            color: "white"
            font.pixelSize: 22
            font.bold: true
            Layout.bottomMargin: 10
        }

        ScrollView {
            id: menuScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: menuScroll.availableWidth
                spacing: 6

                Repeater {
                    model: [
                        ["dashboard", "Tableau de bord", "⌂"],
                        ["students", "Élèves", "👨‍🎓"],
                        ["teachers", "Enseignants", "👨‍🏫"],
                        ["courses", "Cours", "📚"],
                        ["exams", "Examens & notes", "📝"],
                        ["curriculum", "Matières & emploi du temps", "📐"],
                        ["attendance", "Présences", "✅"],
                        ["discipline", "Discipline", "⚠"],
                        ["council", "Délibérations", "🎓"],
                        ["administration", "Administration scolaire", "🏛"],
                        ["finreports", "Rapports financiers", "📊"],
                        ["treasury", "Caisse, banque et clôtures", "🏦"],
                        ["finextra", "Bourses, affectations et états", "📑"],
                        ["import", "Importation des données", "📥"],
                        ["email", "Rapports par e-mail", "✉"],
                        ["hr", "Ressources humaines", "👥"],
                        ["finance", "Paiements / factures", "💰"],
                        ["accounting", "Comptabilité", "🧾"],
                        ["communication", "Messages / annonces", "💬"],
                        ["accounts", "Comptes / sécurité", "🔐"],
                        ["bulletin", "Bulletins", "📄"],
                        ["audit", "Journal d'audit", "📜"],
                        ["fees", "Frais et soldes", "🏷"],
                        ["roles", "Rôles et permissions", "🛡"]
                    ]
                    delegate: AppButton {
                        Layout.fillWidth: true
                        text: modelData[2] + "  " + modelData[1]
                        visible: root.pageAllowed(modelData[0])
                        highlighted: root.currentPage === modelData[0]
                        onClicked: root.navigate(modelData[0])
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: "#1C4363"
        }

        Label {
            text: school.currentUser
            color: "white"
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.topMargin: 6
        }

        Label {
            text: school.currentRole
            color: "#B9D7EF"
            font.pixelSize: 12
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        AppButton {
            Layout.fillWidth: true
            Layout.topMargin: 6
            text: "⚙  Paramètres"
            highlighted: root.currentPage === "settings"
            onClicked: root.navigate("settings")
        }

        AppButton {
            Layout.fillWidth: true
            text: "⎋  Déconnexion"
            onClicked: school.logout()
        }
    }
}
QML

python3 <<'PY'
def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

mq = 'qml/Main.qml'
edit(mq, 'ApplicationWindow {\n    id: win\n    width: 1440\n    height: 900\n',
     'import QtQuick.Window\n\nApplicationWindow {\n    id: win\n    width: 1440\n    height: 900\n    minimumWidth: 900\n    minimumHeight: 600\n    visibility: Window.Maximized\n    onWidthChanged: sidebarOpen = width >= 1200\n    Component.onCompleted: sidebarOpen = width >= 1200\n')

s = open(mq, encoding='utf-8').read()
start = s.index('                    StackLayout {\n                        id: pages\n')
end_marker = '\n                    }\n'
end = s.index(end_marker, start) + len(end_marker)
block = s[start:end]
block2 = block.replace('                        Layout.fillWidth: true\n                        Layout.fillHeight: true\n',
                       '                        width: Math.max(hScroll.width, 980)\n                        height: hScroll.height\n', 1)
assert block2 != block
flick = ('                    Flickable {\n'
         '                        id: hScroll\n'
         '                        Layout.fillWidth: true\n'
         '                        Layout.fillHeight: true\n'
         '                        clip: true\n'
         '                        contentWidth: pages.width\n'
         '                        contentHeight: pages.height\n'
         '                        flickableDirection: Flickable.HorizontalFlick\n'
         '                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }\n\n')
s = s[:start] + flick + block2 + '                    }\n' + s[end:]
open(mq, 'w', encoding='utf-8').write(s)
print("phase 19 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "ui: adaptation à tout écran (menu défilant, repli automatique, défilement horizontal des pages, plein écran)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-adaptation-ecran."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-adaptation-ecran"
