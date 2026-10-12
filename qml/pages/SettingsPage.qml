import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    ColumnLayout {
        anchors.fill: parent
        spacing: 18

        Label {
            text: "Paramètres"
            font.pixelSize: 28
            font.bold: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: accountColumn.implicitHeight + 40
            radius: 12
            color: "white"
            border.color: "#E5EAEE"

            ColumnLayout {
                id: accountColumn
                anchors.fill: parent
                anchors.margins: 20
                spacing: 8

                Label {
                    text: "Compte"
                    font.pixelSize: 18
                    font.bold: true
                }

                Label { text: "Nom : " + school.currentUser }
                Label { text: "Rôle : " + school.currentRole }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
