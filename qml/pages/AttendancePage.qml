import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var rows: []
    readonly property var statusLabels: ["Présent", "Absent", "Retard", "Excusé"]
    readonly property var statusCodes: ["present", "absent", "late", "excused"]

    function statusIndex(code) {
        var i = statusCodes.indexOf(code)
        return i < 0 ? 0 : i
    }
    function refresh() {
        if (!classBox.currentText || !dayField.text) { rows = []; return }
        rows = school.attendanceFor(classBox.currentText, dayField.text)
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Label { text: "Présences"; font.pixelSize: 28; font.bold: true }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            ComboBox { id: classBox; Layout.preferredWidth: 200; model: school.classes(); onCurrentTextChanged: root.refresh() }
            AppTextField { id: dayField; text: Qt.formatDate(new Date(), "yyyy-MM-dd"); Layout.preferredWidth: 170; onTextChanged: root.refresh() }
            Label { text: "(date AAAA-MM-JJ)"; color: "#667085" }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: "white"; border.color: "#E3E8EE"
            ListView {
                anchors.fill: parent; anchors.margins: 12; clip: true
                model: root.rows
                delegate: RowLayout {
                    width: ListView.view.width
                    height: 48
                    Label { text: modelData.name; Layout.fillWidth: true }
                    ComboBox {
                        Layout.preferredWidth: 160
                        model: root.statusLabels
                        currentIndex: root.statusIndex(modelData.status)
                        onActivated: function(index) { school.setAttendance(modelData.studentId, dayField.text, root.statusCodes[index]) }
                    }
                }
            }
        }
    }
}
