import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    signal createRequested()
    property var rows: []
    property string searchText: ""

    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ConfirmDelete {
        id: confirmDel
        message: "Supprimer cet enseignant ? Son compte ne pourra plus se connecter."
        onConfirmed: function(id) { school.deleteTeacher(id) }
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
                    Label { text: modelData.name; width: 170; elide: Text.ElideRight }
                    Label { text: modelData.email; width: 210; elide: Text.ElideRight }
                    Label { text: modelData.subject; width: 160; elide: Text.ElideRight }
                    Label { text: modelData.contact; width: 140 }
                    Label { text: modelData.status; width: 90 }
                    AppButton { text: "Supprimer"; onClicked: confirmDel.ask(modelData.id) }
                }
            }
        }
    }

    function refresh() { rows = school.teachers(searchText) }
}
