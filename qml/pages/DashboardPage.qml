import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ESCATO

ScrollView {
    clip: true
    ColumnLayout {
        width: parent.width
        spacing: 22

        Label { text: "Tableau de bord"; font.pixelSize: 30; font.bold: true }
        Label { text: "Vue centralisée de l'établissement"; color: "#667085" }

        RowLayout {
            spacing: 15
            StatCard { title: "Élèves"; value: school.studentCount }
            StatCard { title: "Enseignants"; value: school.teacherCount }
            StatCard { title: "Cours"; value: school.courseCount }
            StatCard { title: "Factures en attente"; value: school.pendingInvoiceCount }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 170
            radius: 16
            color: "#0B2A43"
            Column {
                anchors.fill: parent; anchors.margins: 25; spacing: 10
                Label { text: "Gestion centralisée"; color: "white"; font.pixelSize: 23; font.bold: true }
                Label { text: "Élèves • Enseignants • Cours • Examens • Paiements • Communication"; color: "#D9EAF7" }
                Label { text: "Les modules sont séparés dans le code tout en partageant la même base SQLite."; color: "#B9D7EF" }
            }
        }
    }
}
