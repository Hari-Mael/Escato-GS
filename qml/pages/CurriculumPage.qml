import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var subjectRows: []
    property var assignmentRows: []
    property var slotRows: []
    property var teacherRows: []
    readonly property var dayNames: ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]

    function refresh() {
        subjectRows = school.subjects()
        teacherRows = school.users("enseignant")
        refreshClass()
    }
    function refreshClass() {
        if (!classBox.currentText) return
        assignmentRows = school.classAssignments(classBox.currentText)
        slotRows = school.timetableSlots(classBox.currentText)
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 18

            Label { text: "Matières, affectations et emploi du temps"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: subjectColumn.implicitHeight + 40
                ColumnLayout {
                    id: subjectColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Matières"; font.pixelSize: 18; font.bold: true }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: subjectName; placeholderText: "Nom de la matière"; Layout.fillWidth: true }
                        AppTextField { id: subjectCoef; placeholderText: "Coefficient"; Layout.preferredWidth: 130; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: {
                                if (school.addSubject({name: subjectName.text, coefficient: parseFloat(subjectCoef.text.replace(",", ".")) || 0})) {
                                    subjectName.text = ""; subjectCoef.text = ""
                                }
                            }
                        }
                    }
                    Repeater {
                        model: root.subjectRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.fillWidth: true }
                            AppTextField { id: coefEdit; text: String(modelData.coefficient); Layout.preferredWidth: 110; inputMethodHints: Qt.ImhDigitsOnly }
                            AppButton {
                                text: "Enregistrer"
                                onClicked: school.updateSubject(modelData.id, {name: modelData.name, coefficient: parseFloat(coefEdit.text.replace(",", ".")) || 0})
                            }
                            AppButton { text: "Supprimer"; onClicked: school.deleteSubject(modelData.id) }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: classColumn.implicitHeight + 40
                ColumnLayout {
                    id: classColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Classe"; font.pixelSize: 18; font.bold: true }
                        ComboBox {
                            id: classBox
                            Layout.preferredWidth: 200
                            model: school.classes()
                            onCurrentTextChanged: root.refreshClass()
                        }
                    }

                    Label { text: "Affectation des enseignants"; font.bold: true; color: "#0B2A43" }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        ComboBox { id: assignSubject; Layout.preferredWidth: 220; model: root.subjectRows; textRole: "name"; valueRole: "id" }
                        ComboBox { id: assignTeacher; Layout.preferredWidth: 240; model: root.teacherRows; textRole: "name"; valueRole: "id" }
                        AppButton {
                            text: "Affecter"; highlighted: true
                            onClicked: school.setClassAssignment(classBox.currentText, assignSubject.currentValue, assignTeacher.currentValue)
                        }
                    }
                    Repeater {
                        model: root.assignmentRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.subject; Layout.fillWidth: true }
                            Label { text: modelData.teacher; color: "#667085" }
                            AppButton { text: "Retirer"; onClicked: school.deleteClassAssignment(modelData.id) }
                        }
                    }

                    Label { text: "Emploi du temps"; font.bold: true; color: "#0B2A43" }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        ComboBox { id: slotDay; Layout.preferredWidth: 130; model: root.dayNames }
                        AppTextField { id: slotStart; text: "08:00"; Layout.preferredWidth: 90 }
                        AppTextField { id: slotEnd; text: "09:00"; Layout.preferredWidth: 90 }
                        ComboBox { id: slotSubject; Layout.preferredWidth: 180; model: root.subjectRows; textRole: "name"; valueRole: "id" }
                        AppTextField { id: slotRoom; placeholderText: "Salle"; Layout.preferredWidth: 110 }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: school.addTimetableSlot({className: classBox.currentText, weekday: slotDay.currentIndex + 1,
                                                                start: slotStart.text, end: slotEnd.text,
                                                                subjectId: slotSubject.currentValue, room: slotRoom.text})
                        }
                    }
                    Repeater {
                        model: root.slotRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: root.dayNames[modelData.weekday - 1]; Layout.preferredWidth: 110 }
                            Label { text: modelData.startTime + " – " + modelData.endTime; Layout.preferredWidth: 130 }
                            Label { text: modelData.subject; Layout.fillWidth: true }
                            Label { text: modelData.room; color: "#667085" }
                            AppButton { text: "Supprimer"; onClicked: school.deleteTimetableSlot(modelData.id) }
                        }
                    }
                }
            }
        }
    }
}
