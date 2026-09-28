import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    signal registerRequested()
    signal detailRequested(int id)
    property string selectedClass: ""
    property string searchText: ""
    property var rows: []

    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ColumnLayout {
        anchors.fill: parent; spacing: 15

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Liste des élèves"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            Button { text: "➕ Inscrire un élève"; highlighted: true; onClicked: registerRequested() }
            Button { text: "🖨 Print list"; onClicked: printer.printStudentList(selectedClass) }
        }

        RowLayout {
            Layout.fillWidth: true
            TextField { Layout.fillWidth: true; placeholderText: "Rechercher nom, prénom ou matricule"; onTextChanged: { searchText=text; refresh() } }
            ComboBox { model: ["Toutes les classes"].concat(school.classes()); onCurrentTextChanged: { selectedClass=currentIndex===0?"":currentText; refresh() } }
            Button { text: "Actualiser"; onClicked: refresh() }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: "white"; border.color: "#E3E8EE"
            ListView {
                id: list; anchors.fill: parent; anchors.margins: 12; clip: true; model: rows
                header: Rectangle {
                    width: list.width; height: 45; color: "#EEF3F7"
                    Row { anchors.fill: parent; anchors.leftMargin: 12
                        Label { text:"Matricule"; width:130; font.bold:true }
                        Label { text:"Nom"; width:150; font.bold:true }
                        Label { text:"Prénom"; width:150; font.bold:true }
                        Label { text:"Classe"; width:110; font.bold:true }
                        Label { text:"Téléphone parent"; width:150; font.bold:true }
                        Label { text:""; width:100 }
                    }
                }
                delegate: Rectangle {
                    width:list.width; height:55; color:index%2?"#FAFBFC":"white"
                    Row { anchors.fill:parent; anchors.leftMargin:12
                        Label { text:modelData.matricule; width:130 }
                        Label { text:modelData.lastName; width:150 }
                        Label { text:modelData.firstName; width:150 }
                        Label { text:modelData.className; width:110; font.bold:true }
                        Label { text:modelData.parentPhone; width:150 }
                        Button { text:"Profil"; onClicked: detailRequested(modelData.id) }
                    }
                }
            }
        }
    }

    function refresh() { rows = school.students(selectedClass, searchText) }
}
