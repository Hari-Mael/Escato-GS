import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: root
    property string path: ""
    property int size: 120
    signal photoChanged(string newPath)

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(size, row.implicitHeight)

    RowLayout {
        id: row
        spacing: 16

        Rectangle {
            Layout.preferredWidth: root.size
            Layout.preferredHeight: root.size
            radius: 12
            color: "#E6F6F4"
            clip: true

            Image {
                anchors.fill: parent
                source: school.photoUrl(root.path)
                visible: root.path !== ""
                fillMode: Image.PreserveAspectCrop
                smooth: true
                mipmap: true
            }
            Text {
                anchors.centerIn: parent
                visible: root.path === ""
                text: "Aucune photo"
                color: "#667085"
                font.pixelSize: 12
            }
        }

        ColumnLayout {
            spacing: 8
            AppButton {
                text: "Changer la photo"
                highlighted: true
                onClicked: dialog.open()
            }
            AppButton {
                text: "Retirer la photo"
                visible: root.path !== ""
                onClicked: {
                    root.path = ""
                    root.photoChanged("")
                }
            }
        }
    }

    FileDialog {
        id: dialog
        title: "Choisir une photo"
        nameFilters: ["Images (*.jpg *.jpeg *.png)"]
        onAccepted: {
            const stored = school.importPhoto(selectedFile.toString())
            if (stored !== "") {
                root.path = stored
                root.photoChanged(stored)
            }
        }
    }
}
