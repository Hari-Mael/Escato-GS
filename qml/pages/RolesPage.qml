import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var matrix: []
    readonly property var roleKeys: ["administrateur", "enseignant", "eleve", "parent", "comptable"]
    readonly property var roleLabels: ["Administrateur", "Enseignant", "Élève", "Parent", "Comptable"]

    function refresh() {
        matrix = school.permissionMatrix()
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 12

            Label { text: "Rôles et permissions"; font.pixelSize: 28; font.bold: true }
            Label {
                text: "Cochez ce que chaque rôle peut faire. Les changements sont appliqués immédiatement et enregistrés dans le journal d'audit."
                color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Droit"; font.bold: true; color: "#667085"; Layout.fillWidth: true }
                Repeater {
                    model: root.roleLabels
                    delegate: Label {
                        text: modelData; font.bold: true; color: "#667085"
                        Layout.preferredWidth: 110; horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Repeater {
                model: root.matrix
                delegate: Rectangle {
                    id: rowItem
                    property var row: modelData
                    Layout.fillWidth: true
                    implicitHeight: rowLayout.implicitHeight + 16
                    radius: 10
                    color: "white"
                    border.color: "#E5EAEE"

                    RowLayout {
                        id: rowLayout
                        anchors.fill: parent
                        anchors.margins: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label { text: rowItem.row.label; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Label { text: rowItem.row.group; color: "#667085"; font.pixelSize: 11 }
                        }

                        Repeater {
                            model: root.roleKeys
                            delegate: CheckBox {
                                Layout.preferredWidth: 110
                                checked: rowItem.row.roles[modelData] === true
                                enabled: !(modelData === "administrateur" && rowItem.row.key === "roles.manage")
                                onToggled: {
                                    school.setPermission(modelData, rowItem.row.key, checked)
                                    root.refresh()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
