import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    property var dash: ({})
    property var accounts: []
    property var expenseAccounts: []
    property bool messageOk: true
    property var expensesModel: []
    property var journalModel: []
    property var balanceModel: []
    property string message: ""

    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Comptabilité"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            Button { text: "Actualiser"; onClicked: refresh() }
        }

        RowLayout {
            Layout.fillWidth: true
            Repeater {
                model: [
                    ["Caisse", dash.cash || 0],
                    ["Banque", dash.bank || 0],
                    ["Écolages", dash.revenue || 0],
                    ["Dépenses", dash.expenses || 0],
                    ["Impayés", dash.receivables || 0]
                ]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 82
                    radius: 10
                    color: "white"
                    border.color: "#DCE5ED"
                    Column { anchors.centerIn: parent; spacing: 4; Label { text: modelData[0]; color: "#637381" } Label { text: Number(modelData[1]).toLocaleString(Qt.locale(), 'f', 0) + " Ar"; font.pixelSize: 20; font.bold: true } }
                }
            }
        }

        TabBar {
            id: tabs
            Layout.fillWidth: true
            TabButton { text: "Dépenses" }
            TabButton { text: "Journal" }
            TabButton { text: "Balance" }
            TabButton { text: "Plan comptable" }
            TabButton { text: "Excel / Sage / Odoo" }
        }

        StackLayout {
            currentIndex: tabs.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                ColumnLayout { anchors.fill: parent; spacing: 10
                    RowLayout { Layout.fillWidth: true
                        TextField { id: cat; placeholderText: "Catégorie"; Layout.preferredWidth: 150 }
                        TextField { id: desc; placeholderText: "Description"; Layout.fillWidth: true }
                        TextField { id: amount; placeholderText: "Montant"; inputMethodHints: Qt.ImhDigitsOnly; Layout.preferredWidth: 120 }
                        ComboBox { id: method; model: ["especes","virement","mvola","orange_money","airtel_money"] }
                        ComboBox { id: acct; model: expenseAccounts; textRole: "label"; Layout.preferredWidth: 220 }
                        Button { text: "Enregistrer"; onClicked: { var a = Number(amount.text.replace(',', '.')); if (!cat.text || !desc.text || !(a > 0)) { messageOk = false; message = 'Catégorie, description et montant (> 0) sont obligatoires.'; return } if (school.addExpense({date: Qt.formatDate(new Date(), 'yyyy-MM-dd'), category: cat.text, description: desc.text, amount: a, method: method.currentText, accountCode: acct.currentIndex >= 0 ? expenseAccounts[acct.currentIndex].code : '606000'})) { cat.text=''; desc.text=''; amount.text=''; messageOk = true; message='Dépense enregistrée' } else { messageOk = false; message = 'Échec de l\'enregistrement de la dépense.' } } }
                    }
                    Label { text: message; color: messageOk ? "#2E7D32" : "#C62828" }
                    ListView { Layout.fillWidth: true; Layout.fillHeight: true; model: expensesModel; clip: true
                        delegate: Rectangle { width: parent.width; height: 48; color: index % 2 ? "#FAFBFC" : "white"; RowLayout { anchors.fill: parent; anchors.margins: 10; Label { text: modelData.date; Layout.preferredWidth: 100 } Label { text: modelData.category; Layout.preferredWidth: 130 } Label { text: modelData.description; Layout.fillWidth: true } Label { text: Number(modelData.amount).toLocaleString(Qt.locale(), 'f', 0) + " Ar"; Layout.preferredWidth: 130 } Label { text: modelData.method; Layout.preferredWidth: 120 } Label { text: modelData.accountCode; Layout.preferredWidth: 90 } } }
                    }
                }
            }

            Item {
                ListView { anchors.fill: parent; model: journalModel; clip: true
                    delegate: Rectangle { width: parent.width; height: 54; color: index % 2 ? "#FAFBFC" : "white"; RowLayout { anchors.fill: parent; anchors.margins: 10; Label { text: modelData.date; Layout.preferredWidth: 100 } Label { text: modelData.journal; Layout.preferredWidth: 90 } Label { text: modelData.accountCode; Layout.preferredWidth: 90 } Label { text: modelData.lineLabel; Layout.fillWidth: true } Label { text: Number(modelData.debit).toLocaleString(Qt.locale(), 'f', 0); Layout.preferredWidth: 120 } Label { text: Number(modelData.credit).toLocaleString(Qt.locale(), 'f', 0); Layout.preferredWidth: 120 } } }
                }
            }

            Item {
                ListView { anchors.fill: parent; model: balanceModel; clip: true
                    delegate: Rectangle { width: parent.width; height: 52; color: index % 2 ? "#FAFBFC" : "white"; RowLayout { anchors.fill: parent; anchors.margins: 10; Label { text: modelData.code; Layout.preferredWidth: 90 } Label { text: modelData.label; Layout.fillWidth: true } Label { text: Number(modelData.debit).toLocaleString(Qt.locale(), 'f', 0); Layout.preferredWidth: 130 } Label { text: Number(modelData.credit).toLocaleString(Qt.locale(), 'f', 0); Layout.preferredWidth: 130 } Label { text: Number(modelData.balance).toLocaleString(Qt.locale(), 'f', 0); Layout.preferredWidth: 130 } } }
                }
            }

            Item {
                ListView { anchors.fill: parent; model: accounts; clip: true
                    delegate: Rectangle { width: parent.width; height: 50; color: index % 2 ? "#FAFBFC" : "white"; RowLayout { anchors.fill: parent; anchors.margins: 10; Label { text: modelData.code; Layout.preferredWidth: 100 } Label { text: modelData.label; Layout.fillWidth: true } Label { text: modelData.type; Layout.preferredWidth: 120 } } }
                }
            }

            Item {
                ColumnLayout { anchors.fill: parent; spacing: 12
                    Label { text: "Exports compatibles avec Microsoft Excel et formats d'échange comptable"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Les exports sont enregistrés dans : " + school.accountingExportDirectory(); wrapMode: Text.Wrap; Layout.fillWidth: true; color: "#637381" }
                    Flow { Layout.fillWidth: true; spacing: 10
                        Button { text: "Paiements → Excel (CSV)"; onClicked: exportKind("payments") }
                        Button { text: "Dépenses → Excel (CSV)"; onClicked: exportKind("expenses") }
                        Button { text: "Journal → Excel (CSV)"; onClicked: exportKind("journal") }
                        Button { text: "Balance → Excel (CSV)"; onClicked: exportKind("trial_balance") }
                        Button { text: "Export Sage 100 (CSV)"; onClicked: exportKind("sage100") }
                        Button { text: "Export Odoo (CSV)"; onClicked: exportKind("odoo") }
                    }
                    Label { text: message; color: messageOk ? "#2E7D32" : "#C62828"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label { text: "Remarque : les formats Sage 100 et Odoo sont des exports structurés à mapper/importer selon la version et le paramétrage du logiciel comptable."; color: "#637381"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    function refresh() {
        dash = school.accountingDashboard()
        accounts = school.chartOfAccounts()
        expenseAccounts = accounts.filter(function(a) { return a.type === 'expense' })
        expensesModel = school.expenses()
        journalModel = school.journal()
        balanceModel = school.trialBalance()
    }
    function exportKind(kind) {
        messageOk = school.exportAccountingCsv(kind)
        message = messageOk ? "Export " + kind + " terminé dans : " + school.accountingExportDirectory() : "Échec de l'export " + kind
    }
}
