import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var studentOptions: []
    property var unallocatedRows: []
    property var openInvoiceRows: []
    property var scholarshipRows: []
    property var categoryRows: []
    property var statement: ({})

    function fmt(n) { return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar" }
    function refreshStudent() {
        var id = studentBox.currentValue
        if (!id) { unallocatedRows = []; openInvoiceRows = []; scholarshipRows = []; return }
        unallocatedRows = school.unallocatedPayments(id)
        openInvoiceRows = school.openInvoices(id)
        scholarshipRows = school.scholarshipsFor(id)
    }
    function refresh() {
        studentOptions = school.students().map(function(s) { return {id: s.id, label: s.lastName + " " + s.firstName + " (" + s.className + ")"} })
        categoryRows = school.expenseCategories()
        refreshStudent()
        statement = school.financialStatements(fromDate.text, toDate.text)
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

            Label { text: "Bourses, affectations et états financiers"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: studentColumn.implicitHeight + 40
                ColumnLayout {
                    id: studentColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Élève"; font.pixelSize: 18; font.bold: true }
                    ComboBox {
                        id: studentBox
                        Layout.fillWidth: true
                        model: root.studentOptions
                        textRole: "label"
                        valueRole: "id"
                        onCurrentValueChanged: root.refreshStudent()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: allocColumn.implicitHeight + 40
                ColumnLayout {
                    id: allocColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Affecter un paiement à une facture"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Un paiement peut couvrir plusieurs factures, ou une facture plusieurs paiements (paiements partiels). Le solde restant de chaque facture est mis à jour."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Repeater {
                        model: root.unallocatedRows
                        delegate: Label {
                            text: "Paiement " + modelData.paidAt + " · " + modelData.method + " · reste à affecter " + root.fmt(modelData.unallocated)
                            Layout.fillWidth: true
                        }
                    }
                    Repeater {
                        model: root.openInvoiceRows
                        delegate: Label {
                            text: "Facture " + modelData.month + " (échéance " + modelData.dueDate + ") · reste à payer " + root.fmt(modelData.remaining)
                            color: "#C62828"; Layout.fillWidth: true
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        ComboBox { id: allocPayment; Layout.preferredWidth: 280; model: root.unallocatedRows; textRole: "label"; valueRole: "id" }
                        ComboBox { id: allocInvoice; Layout.preferredWidth: 260; model: root.openInvoiceRows; textRole: "label"; valueRole: "id" }
                        AppTextField { id: allocAmount; placeholderText: "Montant"; Layout.preferredWidth: 120; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Affecter"; highlighted: true
                            onClicked: school.allocatePayment(allocPayment.currentValue, allocInvoice.currentValue, parseFloat(allocAmount.text.replace(",", ".")) || 0)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: schColumn.implicitHeight + 40
                ColumnLayout {
                    id: schColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Bourses"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Une bourse en pourcentage réduit les mensualités générées après sa création."; color: "#667085"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    Repeater {
                        model: root.scholarshipRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.label; Layout.fillWidth: true }
                            Label { text: modelData.schoolYear; color: "#667085" }
                            Label { text: modelData.percent + " %"; font.bold: true }
                            AppButton { text: "Supprimer"; onClicked: school.deleteScholarship(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: schLabel; placeholderText: "Libellé (ex. Bourse d'excellence)"; Layout.fillWidth: true }
                        AppTextField { id: schPercent; placeholderText: "%"; Layout.preferredWidth: 90; inputMethodHints: Qt.ImhDigitsOnly }
                        AppTextField { id: schYear; placeholderText: "Année (ex. 2026-2027)"; Layout.preferredWidth: 170 }
                        AppButton {
                            text: "Ajouter la bourse"; highlighted: true
                            onClicked: if (school.addScholarship({studentId: studentBox.currentValue, label: schLabel.text,
                                                                  percent: parseFloat(schPercent.text.replace(",", ".")) || 0, schoolYear: schYear.text})) { schLabel.text = ""; schPercent.text = "" }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: catColumn.implicitHeight + 40
                ColumnLayout {
                    id: catColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Catégories de dépenses"; font.pixelSize: 18; font.bold: true }
                    Flow {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            model: root.categoryRows
                            delegate: AppButton {
                                text: modelData.name + "  ✕"
                                onClicked: school.deleteExpenseCategory(modelData.id)
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: catName; placeholderText: "Nouvelle catégorie"; Layout.fillWidth: true }
                        AppButton { text: "Ajouter"; highlighted: true; onClicked: if (school.addExpenseCategory(catName.text)) catName.text = "" }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: stateColumn.implicitHeight + 40
                ColumnLayout {
                    id: stateColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "États financiers et analytiques"; font.pixelSize: 18; font.bold: true }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: fromDate; placeholderText: "Du JJ-MM-AAAA"; Layout.preferredWidth: 160 }
                        AppTextField { id: toDate; placeholderText: "Au JJ-MM-AAAA"; Layout.preferredWidth: 160 }
                        AppButton { text: "Afficher"; highlighted: true; onClicked: root.refresh() }
                    }
                    Label { text: "Produits (encaissements) : " + root.fmt(root.statement.revenue || 0); font.bold: true; color: "#0F9D8F" }
                    Repeater {
                        model: root.statement.byMethod || []
                        delegate: Label { text: "   " + modelData.method + " : " + root.fmt(modelData.amount); color: "#667085" }
                    }
                    Label { text: "Charges (dépenses) : " + root.fmt(root.statement.expenses || 0); font.bold: true; color: "#C62828" }
                    Repeater {
                        model: root.statement.byCategory || []
                        delegate: Label { text: "   " + modelData.category + " : " + root.fmt(modelData.amount) + " (" + modelData.percent + " %)"; color: "#667085" }
                    }
                    Label {
                        text: "Résultat : " + root.fmt(root.statement.result || 0)
                        font.pixelSize: 18; font.bold: true
                        color: (root.statement.result || 0) >= 0 ? "#0F9D8F" : "#C62828"
                    }
                }
            }
        }
    }
}
