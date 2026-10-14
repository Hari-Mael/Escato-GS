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
            Layout.bottomMargin: 18
        }

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

        Item { Layout.fillHeight: true }

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
