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
    property var oneTimeFees: []
    property var bulletin: ({})
    property var bulletinSubjects: []

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function mention(avg) {
        var v = Number(avg)
        if (v >= 16) return "Très bien"
        if (v >= 14) return "Bien"
        if (v >= 12) return "Assez bien"
        if (v >= 10) return "Passable"
        return "Insuffisant"
    }
    function reload() {
        students = school.myStudents()
        if (selectedId === 0 && students.length > 0) selectedId = students[0].id
        refresh()
    }
    function refreshBulletin() {
        if (selectedId <= 0) { bulletin = ({}); bulletinSubjects = []; return }
        bulletin = school.familyBulletin(selectedId, termBox.currentText)
        bulletinSubjects = bulletin.subjects || []
    }
    function refresh() {
        if (selectedId <= 0) {
            detail = ({}); invoices = []; payments = []; oneTimeFees = []
            bulletin = ({}); bulletinSubjects = []
            return
        }
        detail = school.familyStudent(selectedId)
        invoices = school.familyInvoices(selectedId)
        payments = school.familyPayments(selectedId)
        oneTimeFees = school.studentOneTimeFees(selectedId)
        refreshBulletin()
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
                clip: true

                ScrollView {
                    id: scroll
                    anchors.fill: parent
                    anchors.margins: 22
                    clip: true

                    ColumnLayout {
                        width: scroll.availableWidth
                        spacing: 12

                        Label {
                            text: (detail.firstName || "") + " " + (detail.lastName || "")
                            font.pixelSize: 24; font.bold: true; color: "#0B2A43"
                        }
                        Label {
                            text: "Classe : " + (detail.className || "") + "   •   Matricule : " + (detail.matricule || "")
                            color: "#667085"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            radius: 12
                            color: "#F4F7FA"
                            implicitHeight: bulletinColumn.implicitHeight + 32

                            ColumnLayout {
                                id: bulletinColumn
                                x: 16; y: 16
                                width: parent.width - 32
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: "Bulletin"; font.pixelSize: 18; font.bold: true; color: "#0B2A43"; Layout.fillWidth: true }
                                    ComboBox {
                                        id: termBox
                                        Layout.preferredWidth: 170
                                        model: school.terms()
                                        onCurrentTextChanged: root.refreshBulletin()
                                    }
                                    AppButton {
                                        text: "🖨 Imprimer"
                                        onClicked: printer.printBulletin(selectedId, termBox.currentText)
                                    }
                                }
                                Label {
                                    visible: bulletinSubjects.length === 0
                                    text: "Aucune note enregistrée pour ce trimestre."
                                    color: "#667085"
                                }
                                RowLayout {
                                    visible: bulletinSubjects.length > 0
                                    Layout.fillWidth: true
                                    Label { text: "Matière"; font.bold: true; color: "#667085"; Layout.fillWidth: true }
                                    Label { text: "Moyenne /20"; font.bold: true; color: "#667085"; Layout.preferredWidth: 110 }
                                    Label { text: "Appréciation"; font.bold: true; color: "#667085"; Layout.preferredWidth: 130 }
                                }
                                Repeater {
                                    model: bulletinSubjects
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: modelData.subject; Layout.fillWidth: true; elide: Text.ElideRight }
                                        Label { text: Number(modelData.average).toFixed(2); Layout.preferredWidth: 110 }
                                        Label { text: root.mention(modelData.average); color: "#667085"; Layout.preferredWidth: 130 }
                                    }
                                }
                                Label {
                                    visible: bulletinSubjects.length > 0
                                    text: "Moyenne générale : " + (bulletin.generalAverage || "—") + " / 20   •   " + (bulletin.generalAverage ? root.mention(bulletin.generalAverage) : "")
                                    font.pixelSize: 16; font.bold: true; color: "#0B2A43"
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Factures et échéances"; font.pixelSize: 18; font.bold: true; color: "#0B2A43"; Layout.fillWidth: true }
                            AppButton { text: "🖨 Demande de paiement"; onClicked: printer.printPaymentRequest(selectedId) }
                        }
                        Repeater {
                            model: invoices
                            delegate: RowLayout {
                                Layout.fillWidth: true
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

                        Label { text: "Frais ponctuels"; font.pixelSize: 18; font.bold: true; color: "#0B2A43" }
                        Label {
                            visible: oneTimeFees.length === 0
                            text: "Aucun frais ponctuel assigné."
                            color: "#667085"
                        }
                        Repeater {
                            model: oneTimeFees
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                Label { text: modelData.name; Layout.fillWidth: true }
                                Label { text: "échéance " + modelData.dueDate; color: "#667085" }
                                Label { text: fmt(modelData.amount); font.bold: true }
                                Label {
                                    text: modelData.status === "paid" ? "Payé" : "À payer"
                                    color: modelData.status === "paid" ? "#0F9D8F" : "#C62828"
                                    Layout.preferredWidth: 90
                                }
                                AppButton {
                                    visible: modelData.status === "paid"
                                    text: "🧾 Reçu"
                                    onClicked: printer.printReceipt(modelData.paymentId)
                                }
                            }
                        }

                        Label { text: "Paiements et reçus"; font.pixelSize: 18; font.bold: true; color: "#0B2A43" }
                        Repeater {
                            model: payments
                            delegate: RowLayout {
                                Layout.fillWidth: true
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
}
