import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    signal createRequested()
    property var rows: []
    property string searchText: ""
    property int qrId: 0

    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ConfirmDelete {
        id: confirmDel
        message: "Supprimer cet enseignant ? Son compte ne pourra plus se connecter."
        onConfirmed: function(id) { school.deleteTeacher(id) }
    }

    Popup {
        id: qrPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        padding: 20
        background: Rectangle { radius: 14; color: "white" }

        ColumnLayout {
            spacing: 12
            Label { text: "QR code enseignant"; font.pixelSize: 18; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 260
                Layout.preferredHeight: 260
                fillMode: Image.PreserveAspectFit
                smooth: false
                source: school.qrCodePngDataUrl(school.teacherQrText(qrId))
            }
            Label {
                text: "Scanner ce code affiche les informations de l'enseignant (nom, matière, contact)."
                color: "#667085"
                wrapMode: Text.WordWrap
                Layout.preferredWidth: 280
            }
            AppButton { text: "Fermer"; Layout.alignment: Qt.AlignRight; onClicked: qrPopup.close() }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 15

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Enseignants"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            AppButton { text: "➕ Ajouter"; onClicked: createRequested() }
        }

        AppTextField {
            Layout.fillWidth: true
            placeholderText: "Rechercher enseignant, matière, CIN..."
            onTextChanged: searchText = text
            onEditingFinished: refresh()
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: rows
            clip: true
            delegate: Rectangle {
                width: parent.width
                height: 65
                color: index % 2 ? "#FAFBFC" : "white"
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    Label { text: modelData.name; width: 160; elide: Text.ElideRight }
                    Label { text: modelData.email; width: 190; elide: Text.ElideRight }
                    Label { text: modelData.subject; width: 130; elide: Text.ElideRight }
                    Label { text: modelData.contact; width: 130 }
                    Label { text: modelData.status; width: 80 }
                    AppButton { text: "QR"; onClicked: { qrId = modelData.id; qrPopup.open() } }
                    AppButton { text: "Supprimer"; onClicked: confirmDel.ask(modelData.id) }
                }
            }
        }
    }

    function refresh() { rows = school.teachers(searchText) }
}
