import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    color: "#F4F7FA"

    property var students: []
    property int selectedId: 0
    property var detail: ({})
    property var invoices: []
    property var payments: []

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function reload() {
        students = school.myStudents()
        if (selectedId === 0 && students.length > 0) selectedId = students[0].id
        refresh()
    }
    function refresh() {
        if (selectedId <= 0) { detail = ({}); invoices = []; payments = []; return }
        detail = school.familyStudent(selectedId)
        invoices = school.familyInvoices(selectedId)
        payments = school.familyPayments(selectedId)
    }
    onSelectedIdChanged: refresh()
    Component.onCompleted: reload()
    Connections { target: school; function onDataChanged() { reload() } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Espace famille"; font.pixelSize: 28; font.bold: true; color: "#0B2A43" }
            Item { Layout.fillWidth: true }
            Label { text: school.currentUser; color: "#667085" }
            AppButton { text: "⎋  Déconnexion"; onClicked: school.logout() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                radius: 16
                color: "white"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Label { text: "Mes enfants"; font.pixelSize: 18; font.bold: true; color: "#0B2A43" }
                    Label {
                        visible: students.length === 0
                        text: "Aucun élève n'est rattaché à votre compte. Adressez-vous à l'administration."
                        wrapMode: Text.WordWrap; color: "#667085"; Layout.fillWidth: true
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: students
                        delegate: AppButton {
                            width: ListView.view.width
                            text: modelData.lastName + " " + modelData.firstName + "  (" + modelData.className + ")"
                            highlighted: modelData.id === selectedId
                            onClicked: selectedId = modelData.id
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: "white"
                visible: selectedId > 0

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12

                    Label {
                        text: (detail.firstName || "") + " " + (detail.lastName || "")
                        font.pixelSize: 24; font.bold: true; color: "#0B2A43"
                    }
                    Label {
                        text: "Classe : " + (detail.className || "") + "   •   Matricule : " + (detail.matricule || "")
                        color: "#667085"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Factures et échéances"; font.pixelSize: 18; font.bold: true; color: "#0B2A43"; Layout.fillWidth: true }
                        AppButton { text: "🖨 Demande de paiement"; onClicked: printer.printPaymentRequest(selectedId) }
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 170
                        clip: true
                        model: invoices
                        delegate: RowLayout {
                            width: ListView.view.width
                            Label { text: modelData.month; Layout.preferredWidth: 140 }
                            Label { text: "échéance " + modelData.dueDate; color: "#667085"; Layout.fillWidth: true }
                            Label { text: fmt(modelData.amount); font.bold: true }
                            Label {
                                text: modelData.status === "paid" ? "Payé" : modelData.status === "late" ? "En retard" : "À payer"
                                color: modelData.status === "paid" ? "#0F9D8F" : "#C62828"
                                Layout.preferredWidth: 90
                            }
                        }
                    }

                    Label { text: "Paiements et reçus"; font.pixelSize: 18; font.bold: true; color: "#0B2A43" }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: payments
                        delegate: RowLayout {
                            width: ListView.view.width
                            Label { text: modelData.paidAt; Layout.preferredWidth: 160 }
                            Label { text: modelData.method; color: "#667085"; Layout.fillWidth: true }
                            Label { text: fmt(modelData.amount); font.bold: true }
                            AppButton { text: "🧾 Reçu"; onClicked: printer.printReceipt(modelData.id) }
                        }
                    }
                }
            }
        }
    }
}
