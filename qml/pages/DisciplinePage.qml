import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var studentOptions: []
    property var incidentRows: []

    function refreshStudents() {
        studentOptions = school.students().map(function(s) {
            return {id: s.id, label: s.lastName + " " + s.firstName + " (" + s.className + ")"}
        })
    }
    function refreshIncidents() {
        var id = studentBox.currentValue
        incidentRows = id ? school.incidents(id) : []
    }
    Component.onCompleted: refreshStudents()
    Connections {
        target: school
        function onDataChanged() { root.refreshStudents(); root.refreshIncidents() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Label { text: "Discipline"; font.pixelSize: 28; font.bold: true }

        Rectangle {
            Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
            implicitHeight: formColumn.implicitHeight + 32
            ColumnLayout {
                id: formColumn
                x: 16; y: 16; width: parent.width - 32; spacing: 8
                ComboBox {
                    id: studentBox
                    Layout.fillWidth: true
                    model: root.studentOptions
                    textRole: "label"
                    valueRole: "id"
                    onCurrentValueChanged: root.refreshIncidents()
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    AppTextField { id: incDate; text: Qt.formatDate(new Date(), "yyyy-MM-dd"); Layout.preferredWidth: 150 }
                    AppTextField { id: incCategory; placeholderText: "Catégorie (ex. Comportement)"; Layout.preferredWidth: 220 }
                    AppTextField { id: incSanction; placeholderText: "Sanction (ex. Avertissement)"; Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    AppTextField { id: incDescription; placeholderText: "Description des faits"; Layout.fillWidth: true }
                    AppButton {
                        text: "Enregistrer l'incident"; highlighted: true
                        onClicked: {
                            if (school.addIncident({studentId: studentBox.currentValue, date: incDate.text,
                                                    category: incCategory.text, description: incDescription.text,
                                                    sanction: incSanction.text})) {
                                incCategory.text = ""; incDescription.text = ""; incSanction.text = ""
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: "white"; border.color: "#E3E8EE"
            ListView {
                anchors.fill: parent; anchors.margins: 12; clip: true
                model: root.incidentRows
                delegate: RowLayout {
                    width: ListView.view.width
                    Label { text: modelData.date; Layout.preferredWidth: 110 }
                    Label { text: modelData.category; Layout.preferredWidth: 180; font.bold: true }
                    Label { text: modelData.description; Layout.fillWidth: true; elide: Text.ElideRight }
                    Label { text: modelData.sanction; color: "#667085" }
                }
            }
        }
    }
}
