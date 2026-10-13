import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ESCATO
import "../components"

ScrollView {
    id: root
    clip: true

    property var stats: ({})

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function refresh() {
        stats = school.monthlyStats()
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        width: root.availableWidth
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

        RowLayout {
            spacing: 15
            StatCard { title: "Paiements ce mois"; value: root.fmt(root.stats.paidAmount || 0) }
            StatCard { title: "Factures en retard"; value: String(root.stats.lateCount || 0) }
            StatCard { title: "Reste à recouvrer"; value: root.fmt(root.stats.dueAmount || 0) }
            StatCard { title: "Retards ce mois"; value: String(root.stats.tardinessCount || 0) }
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
