import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    signal registerRequested()
    signal detailRequested(int id)
    property string selectedClass: ""
    property string searchText: ""
    property var rows: []
    property int statusIndex: 0

    function matchesStatus(s) {
        var graduated = !!s.graduatedAt
        var active = (s.accountStatus || "active") === "active"
        if (statusIndex === 1) return !graduated && active
        if (statusIndex === 2) return !graduated && !active
        if (statusIndex === 3) return graduated
        return true
    }

    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ColumnLayout {
        anchors.fill: parent; spacing: 15

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Liste des élèves"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            AppButton { text: "➕ Inscrire un élève"; highlighted: true; onClicked: registerRequested() }
            AppButton { text: "🖨 Print list"; onClicked: printer.printStudentList(selectedClass) }
        }

        RowLayout {
            Layout.fillWidth: true
            AppTextField { Layout.fillWidth: true; placeholderText: "Rechercher nom, prénom ou matricule"; onTextChanged: { searchText=text; refresh() } }
            ComboBox { model: ["Toutes les classes"].concat(school.classes()); onCurrentTextChanged: { selectedClass=currentIndex===0?"":currentText; refresh() } }
            ComboBox {
                Layout.preferredWidth: 170
                model: ["Tous les statuts", "Actifs", "Bloqués", "Diplômés"]
                onCurrentIndexChanged: { statusIndex = currentIndex; refresh() }
            }
            AppButton { text: "Actualiser"; onClicked: refresh() }
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
                        Label { text:modelData.lastName; width:150; color:"#0B7F74"; font.underline:true
                            MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked: infoPopup.show(modelData.lastName + " " + modelData.firstName, studentInfo(modelData)) } }
                        Label { text:modelData.firstName; width:150; color:"#0B7F74"; font.underline:true
                            MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked: infoPopup.show(modelData.lastName + " " + modelData.firstName, studentInfo(modelData)) } }
                        Label { text:modelData.className; width:110; font.bold:true }
                        Label { text:modelData.parentPhone; width:150 }
                        AppButton { text:"Profil"; onClicked: detailRequested(modelData.id) }
                    }
                }
            }
        }
    }

    InfoPopup { id: infoPopup }

    function studentInfo(s) {
        return [
            ["Matricule", s.matricule],
            ["Nom", s.lastName],
            ["Prénom", s.firstName],
            ["Date de naissance", s.birthDate],
            ["Lieu de naissance", s.birthPlace],
            ["Classe", s.className],
            ["Date d'entrée", s.entryDate],
            ["Téléphone parent", s.parentPhone],
            ["E-mail parent", s.parentEmail],
            ["Adresse", s.address],
            ["Ancienne école", s.previousSchool],
            ["Ancienne classe", s.previousClass],
            ["Projet / carrière", s.desiredCareer],
            ["Statut du compte", s.accountStatus],
            ["Paiements manqués", s.missedPayments]
        ]
    }

    function refresh() { rows = school.students(selectedClass, searchText).filter(matchesStatus) }
}
