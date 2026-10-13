import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    color: "#092B45"
    clip: true
    property string currentPage: "dashboard"
    signal navigate(string page)

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
