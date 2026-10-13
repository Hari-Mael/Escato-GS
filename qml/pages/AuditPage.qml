import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    property var rows: []

    function refresh() {
        rows = school.auditLogs(300)
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Journal d'audit"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            AppButton { text: "Actualiser"; onClicked: refresh() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: "white"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Date"; font.bold: true; color: "#667085"; Layout.preferredWidth: 170 }
                    Label { text: "Utilisateur"; font.bold: true; color: "#667085"; Layout.preferredWidth: 160 }
                    Label { text: "Action"; font.bold: true; color: "#667085"; Layout.preferredWidth: 110 }
                    Label { text: "Objet"; font.bold: true; color: "#667085"; Layout.preferredWidth: 170 }
                    Label { text: "Détails"; font.bold: true; color: "#667085"; Layout.fillWidth: true }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: rows
                    delegate: RowLayout {
                        width: ListView.view.width
                        Label { text: modelData.createdAt; Layout.preferredWidth: 170 }
                        Label { text: modelData.user; Layout.preferredWidth: 160; elide: Text.ElideRight }
                        Label { text: modelData.action; Layout.preferredWidth: 110 }
                        Label {
                            text: modelData.entity + (modelData.entityId ? " #" + modelData.entityId : "")
                            Layout.preferredWidth: 170; elide: Text.ElideRight
                        }
                        Label { text: modelData.details; color: "#667085"; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
            }
        }
    }
}
