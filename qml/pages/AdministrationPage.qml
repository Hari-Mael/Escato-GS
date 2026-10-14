import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property bool canStructure: false
    property bool canCalendar: false
    property var cycleRows: []
    property var levelRows: []
    property var classRows: []
    property var roomRows: []
    property var eventRows: []
    readonly property var eventKinds: ["evenement", "ferie", "vacances"]
    readonly property var eventLabels: ["Événement", "Jour férié", "Vacances"]

    function refreshPerms() {
        canStructure = school.can("structure.manage")
        canCalendar = school.can("calendar.manage")
    }
    function refresh() {
        refreshPerms()
        cycleRows = school.cycles()
        levelRows = school.levels()
        classRows = school.schoolClasses()
        roomRows = school.rooms()
        eventRows = school.calendarEvents()
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

            Label { text: "Administration scolaire"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: cycleColumn.implicitHeight + 40
                ColumnLayout {
                    id: cycleColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Cycles scolaires"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.cycleRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.fillWidth: true }
                            AppButton { text: "Supprimer"; visible: root.canStructure; onClicked: school.deleteCycle(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canStructure
                        AppTextField { id: cycleName; placeholderText: "Nouveau cycle"; Layout.fillWidth: true }
                        AppButton { text: "Ajouter"; highlighted: true; onClicked: if (school.addCycle(cycleName.text)) cycleName.text = "" }
                    }

                    Label { text: "Niveaux scolaires"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.levelRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.fillWidth: true }
                            Label { text: modelData.cycleName; color: "#667085" }
                            AppButton { text: "Supprimer"; visible: root.canStructure; onClicked: school.deleteLevel(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canStructure
                        AppTextField { id: levelName; placeholderText: "Nouveau niveau (ex. CP)"; Layout.fillWidth: true }
                        ComboBox { id: levelCycle; Layout.preferredWidth: 180; model: root.cycleRows; textRole: "name"; valueRole: "id" }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: if (school.addLevel(levelName.text, levelCycle.currentValue)) levelName.text = ""
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: classColumn.implicitHeight + 40
                ColumnLayout {
                    id: classColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Classes"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Une classe désactivée n'apparaît plus dans les listes, mais ses élèves et son historique sont conservés."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Repeater {
                        model: root.classRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; font.bold: true; Layout.preferredWidth: 140 }
                            Label { text: modelData.cycleName + " · " + modelData.levelName; color: "#667085"; Layout.fillWidth: true }
                            Label { text: modelData.isActive ? "Active" : "Désactivée"; color: modelData.isActive ? "#0F9D8F" : "#C62828" }
                            AppButton {
                                text: modelData.isActive ? "Désactiver" : "Réactiver"
                                visible: root.canStructure
                                onClicked: school.setSchoolClassActive(modelData.id, !modelData.isActive)
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canStructure
                        AppTextField { id: className; placeholderText: "Nom de la classe (ex. CE3)"; Layout.fillWidth: true }
                        ComboBox { id: classLevel; Layout.preferredWidth: 200; model: root.levelRows; textRole: "name"; valueRole: "id" }
                        AppButton {
                            text: "Ajouter la classe"; highlighted: true
                            onClicked: if (school.addSchoolClass(className.text, classLevel.currentValue)) className.text = ""
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: roomColumn.implicitHeight + 40
                ColumnLayout {
                    id: roomColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Salles"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.roomRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; font.bold: true; Layout.fillWidth: true }
                            Label { text: modelData.capacity > 0 ? modelData.capacity + " places" : ""; color: "#667085" }
                            AppButton { text: "Supprimer"; visible: root.canStructure; onClicked: school.deleteRoom(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canStructure
                        AppTextField { id: roomName; placeholderText: "Nom de la salle"; Layout.fillWidth: true }
                        AppTextField { id: roomCapacity; placeholderText: "Places"; Layout.preferredWidth: 110; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: if (school.addRoom(roomName.text, parseInt(roomCapacity.text) || 0)) { roomName.text = ""; roomCapacity.text = "" }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: calendarColumn.implicitHeight + 40
                ColumnLayout {
                    id: calendarColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Calendrier scolaire"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.eventRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.startDate + (modelData.endDate !== modelData.startDate ? " → " + modelData.endDate : ""); Layout.preferredWidth: 220 }
                            Label { text: modelData.title; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: root.eventLabels[root.eventKinds.indexOf(modelData.kind)]; color: "#667085" }
                            AppButton { text: "Supprimer"; visible: root.canCalendar; onClicked: school.deleteCalendarEvent(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canCalendar
                        AppTextField { id: eventTitle; placeholderText: "Titre (ex. Rentrée, Fête nationale)"; Layout.fillWidth: true }
                        AppTextField { id: eventStart; placeholderText: "Début AAAA-MM-JJ"; Layout.preferredWidth: 150 }
                        AppTextField { id: eventEnd; placeholderText: "Fin AAAA-MM-JJ"; Layout.preferredWidth: 150 }
                        ComboBox { id: eventKind; Layout.preferredWidth: 130; model: root.eventLabels }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: {
                                if (school.addCalendarEvent({title: eventTitle.text, startDate: eventStart.text, endDate: eventEnd.text,
                                                             kind: root.eventKinds[eventKind.currentIndex]})) {
                                    eventTitle.text = ""; eventStart.text = ""; eventEnd.text = ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
