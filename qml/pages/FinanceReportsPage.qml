import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property bool canReports: false
    property int reportIndex: 0
    property var overdueRows: []
    property var classRows: []
    property var parentRows: []
    property var monthRows: []
    property var historyRows: []
    readonly property var reportNames: ["Impayés", "Situation par classe", "Situation par parent", "Tableau financier mensuel", "Historique des documents"]

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function refreshPerms() {
        canReports = school.can("finance.reports")
    }
    function refresh() {
        refreshPerms()
        if (!canReports) return
        overdueRows = school.overdueByStudent(asOfDate.text)
        var all = school.balanceOverview("", "").students || []
        var byClass = {}
        for (var i = 0; i < all.length; ++i) {
            var s = all[i]
            if (!byClass[s.className]) byClass[s.className] = {className: s.className, billed: 0, collected: 0, balance: 0, count: 0}
            byClass[s.className].billed += s.billed
            byClass[s.className].collected += s.collected
            byClass[s.className].balance += s.balance
            byClass[s.className].count += 1
        }
        classRows = Object.keys(byClass).sort().map(function(k) { return byClass[k] })
        parentRows = school.parentBalances()
        monthRows = school.monthlyCollections(parseInt(yearField.text) || new Date().getFullYear())
        historyRows = school.documentHistory(300)
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Label { text: "Rapports financiers"; font.pixelSize: 28; font.bold: true; Layout.fillWidth: true }
            ComboBox {
                id: reportBox
                Layout.preferredWidth: 280
                model: root.reportNames
                onCurrentIndexChanged: root.reportIndex = currentIndex
            }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: 8
            visible: root.reportIndex === 0
            Label { text: "Impayés au" }
            AppTextField { id: asOfDate; Layout.preferredWidth: 160; placeholderText: "AAAA-MM-JJ (vide = aujourd'hui)" }
            AppButton { text: "Actualiser"; highlighted: true; onClicked: root.refresh() }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            visible: root.reportIndex === 3
            Label { text: "Année" }
            AppTextField { id: yearField; text: String(new Date().getFullYear()); Layout.preferredWidth: 100; inputMethodHints: Qt.ImhDigitsOnly; onTextChanged: root.refresh() }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: "white"; border.color: "#E3E8EE"
            visible: root.canReports
            ListView {
                anchors.fill: parent; anchors.margins: 14; clip: true
                model: root.reportIndex === 0 ? root.overdueRows
                     : root.reportIndex === 1 ? root.classRows
                     : root.reportIndex === 2 ? root.parentRows
                     : root.reportIndex === 3 ? root.monthRows
                     : root.historyRows
                delegate: RowLayout {
                    width: ListView.view.width
                    height: 40
                    Label {
                        text: root.reportIndex === 0 ? modelData.name
                            : root.reportIndex === 1 ? modelData.className
                            : root.reportIndex === 2 ? modelData.name
                            : root.reportIndex === 3 ? modelData.label
                            : modelData.createdAt + " · " + modelData.docType + " #" + modelData.refId
                        Layout.fillWidth: true; elide: Text.ElideRight
                    }
                    Label {
                        visible: root.reportIndex === 0
                        text: modelData.className
                        color: "#667085"; Layout.preferredWidth: 120
                    }
                    Label {
                        visible: root.reportIndex === 0 || root.reportIndex === 1 || root.reportIndex === 2 || root.reportIndex === 3
                        text: root.reportIndex === 0 ? root.fmt(modelData.total) + (modelData.oldestDue ? "  (depuis " + modelData.oldestDue + ")" : "")
                            : root.reportIndex === 1 ? root.fmt(modelData.balance)
                            : root.reportIndex === 2 ? root.fmt(modelData.balance)
                            : "encaissé " + root.fmt(modelData.collected) + " / facturé " + root.fmt(modelData.billed)
                        font.bold: true; Layout.preferredWidth: 300
                        color: root.reportIndex === 3 ? "#0B2A43" : (modelData.balance > 0 || modelData.total > 0 ? "#C62828" : "#0F9D8F")
                    }
                    AppButton {
                        visible: root.reportIndex === 0
                        text: "Relancer"
                        onClicked: school.processPaymentReminders()
                    }
                }
            }
        }
    }
}
