import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var rows: []

    function refresh() {
        if (!classBox.currentText || !termBox.currentText) { rows = []; return }
        rows = school.deliberation(classBox.currentText, termBox.currentText)
    }
    function decisionColor(d) {
        if (d === "Admis") return "#0F9D8F"
        if (d === "Rattrapage") return "#B7791F"
        if (d === "Ajourné") return "#C62828"
        return "#667085"
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Label { text: "Délibérations"; font.pixelSize: 28; font.bold: true }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            ComboBox { id: classBox; Layout.preferredWidth: 200; model: school.classes(); onCurrentTextChanged: root.refresh() }
            ComboBox { id: termBox; Layout.preferredWidth: 170; model: school.terms(); onCurrentTextChanged: root.refresh() }
            Label { text: "Admis : moyenne ≥ " + school.setting("pass_mark") + " · Rattrapage : ≥ " + school.setting("retake_mark") + " · Ajourné : < " + school.setting("retake_mark"); color: "#667085" }
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
                    Label { text: modelData.average === "" ? "—" : Number(modelData.average).toFixed(2) + " / 20"; Layout.preferredWidth: 130 }
                    Label { text: modelData.decision; font.bold: true; color: root.decisionColor(modelData.decision); Layout.preferredWidth: 120 }
                    AppButton { text: "🧾 Livret"; onClicked: printer.printBulletin(modelData.studentId, termBox.currentText) }
                }
            }
        }
    }
}
