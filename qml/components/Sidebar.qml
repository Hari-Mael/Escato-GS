import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#092B45"
    property string currentPage: "dashboard"
    signal navigate(string page)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 6

        Label {
            text: "ESCATO"
            color: "white"
            font.pixelSize: 22
            font.bold: true
            Layout.bottomMargin: 18
        }

        Label {
            text: school.currentUser
            color: "#B9D7EF"
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.bottomMargin: 12
        }

        Repeater {
            model: [
                ["dashboard","Tableau de bord","⌂"],
                ["students","Élèves","👨‍🎓"],
                ["teachers","Enseignants","👨‍🏫"],
                ["courses","Cours","📚"],
                ["exams","Examens & notes","📝"],
                ["finance","Paiements / factures","💰"],
                ["accounting","Comptabilité","🧾"],
                ["communication","Messages / annonces","💬"],
                ["accounts","Comptes / sécurité","🔐"],
                ["bulletin","Bulletins","📄"]
            ]
            delegate: Button {
                Layout.fillWidth: true
                text: modelData[2] + "  " + modelData[1]
                highlighted: root.currentPage === modelData[0]
                onClicked: root.navigate(modelData[0])
            }
        }

        Item { Layout.fillHeight: true }

        Button {
            Layout.fillWidth: true
            text: "Déconnexion"
            onClicked: school.logout()
        }
    }
}
