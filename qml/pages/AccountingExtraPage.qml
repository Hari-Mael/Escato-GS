import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var periodRows: []
    property var movementRows: []
    property var closingRows: []
    property var accountRows: []
    property var lineRows: []
    property var unreconciled: []
    property var methodRows: []
    property var studentOptions: []
    property var scheduleRows: []
    property int accountIndex: 0

    function fmt(n) { return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar" }
    function refresh() {
        periodRows = school.accountingPeriods()
        movementRows = school.cashMovements(cashDate.text)
        closingRows = school.cashClosings()
        accountRows = school.bankAccounts()
        var acc = accountRows[accountIndex]
        lineRows = acc ? school.bankLines(acc.id) : []
        unreconciled = school.unreconciledPayments()
        methodRows = school.paymentMethodList()
        studentOptions = school.students().map(function(s) { return {id: s.id, label: s.lastName + " " + s.firstName + " (" + s.className + ")"} })
        refreshSchedule()
    }
    function refreshSchedule() {
        scheduleRows = studentBox.currentValue ? school.studentSchedule(studentBox.currentValue) : []
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

            Label { text: "Caisse, banque et clôtures"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: periodColumn.implicitHeight + 40
                ColumnLayout {
                    id: periodColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Clôtures des périodes comptables"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Une période clôturée refuse tout paiement ou dépense datés dans cette période."; color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Repeater {
                        model: root.periodRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.label; font.bold: true; Layout.preferredWidth: 180 }
                            Label { text: modelData.startDate + " → " + modelData.endDate; color: "#667085"; Layout.fillWidth: true }
                            Label { text: modelData.closed ? "Clôturée" : "Ouverte"; color: modelData.closed ? "#C62828" : "#0F9D8F" }
                            AppButton { text: modelData.closed ? "Rouvrir" : "Clôturer"; onClicked: school.setAccountingPeriodClosed(modelData.id, !modelData.closed) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: periodLabel; placeholderText: "Libellé (ex. Octobre 2026)"; Layout.preferredWidth: 220 }
                        AppTextField { id: periodStart; placeholderText: "Début AAAA-MM-JJ"; Layout.preferredWidth: 150 }
                        AppTextField { id: periodEnd; placeholderText: "Fin AAAA-MM-JJ"; Layout.preferredWidth: 150 }
                        AppButton {
                            text: "Ajouter la période"; highlighted: true
                            onClicked: if (school.addAccountingPeriod({label: periodLabel.text, startDate: periodStart.text, endDate: periodEnd.text})) { periodLabel.text = ""; periodStart.text = ""; periodEnd.text = "" }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: cashColumn.implicitHeight + 40
                ColumnLayout {
                    id: cashColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Caisse"; font.pixelSize: 18; font.bold: true }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: cashDate; text: Qt.formatDate(new Date(), "yyyy-MM-dd"); Layout.preferredWidth: 150; onTextChanged: root.refresh() }
                        Label { text: "Espèces attendues : " + root.fmt(school.cashExpected(cashDate.text).expected || 0); font.bold: true }
                    }
                    Repeater {
                        model: root.movementRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.kind === "entree" ? "Entrée" : "Sortie"; color: modelData.kind === "entree" ? "#0F9D8F" : "#C62828"; Layout.preferredWidth: 80 }
                            Label { text: modelData.label; Layout.fillWidth: true }
                            Label { text: root.fmt(modelData.amount); font.bold: true }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        ComboBox { id: moveKind; Layout.preferredWidth: 120; model: ["Entrée", "Sortie"] }
                        AppTextField { id: moveAmount; placeholderText: "Montant"; Layout.preferredWidth: 130; inputMethodHints: Qt.ImhDigitsOnly }
                        AppTextField { id: moveLabel; placeholderText: "Libellé"; Layout.fillWidth: true }
                        AppButton {
                            text: "Enregistrer le mouvement"
                            onClicked: if (school.addCashMovement({date: cashDate.text, kind: moveKind.currentIndex === 0 ? "entree" : "sortie",
                                                                   amount: parseFloat(moveAmount.text.replace(",", ".")) || 0, label: moveLabel.text})) { moveAmount.text = ""; moveLabel.text = "" }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: countedCash; placeholderText: "Espèces comptées"; Layout.preferredWidth: 180; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Clôturer la caisse du jour"; highlighted: true
                            onClicked: school.closeCash(cashDate.text, parseFloat(countedCash.text.replace(",", ".")) || 0)
                        }
                    }
                    Label { text: "Clôtures de caisse"; font.bold: true; color: "#0B2A43" }
                    Repeater {
                        model: root.closingRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.date; Layout.preferredWidth: 110 }
                            Label { text: "attendu " + root.fmt(modelData.expected) + " · compté " + root.fmt(modelData.counted); Layout.fillWidth: true; color: "#667085" }
                            Label { text: "écart " + root.fmt(modelData.difference); font.bold: true; color: modelData.difference === 0 ? "#0F9D8F" : "#C62828" }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: bankColumn.implicitHeight + 40
                ColumnLayout {
                    id: bankColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Banque et rapprochement"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.accountRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name + " (" + modelData.bank + " ···" + modelData.last4 + ")"; Layout.fillWidth: true }
                            Label { text: "solde " + root.fmt(modelData.balance); font.bold: true }
                            Label { text: modelData.reconciled + "/" + modelData.lines + " rapprochées"; color: "#667085" }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: bankName; placeholderText: "Nom du compte"; Layout.preferredWidth: 180 }
                        AppTextField { id: bankBank; placeholderText: "Banque"; Layout.preferredWidth: 140 }
                        AppTextField { id: bankLast4; placeholderText: "4 derniers chiffres"; Layout.preferredWidth: 150 }
                        AppTextField { id: bankOpening; placeholderText: "Solde initial"; Layout.preferredWidth: 130; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Ajouter le compte"
                            onClicked: school.addBankAccount({name: bankName.text, bank: bankBank.text, last4: bankLast4.text, openingBalance: parseFloat(bankOpening.text.replace(",", ".")) || 0})
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        ComboBox { id: accountBox; Layout.preferredWidth: 260; model: root.accountRows; textRole: "name"; onCurrentIndexChanged: { root.accountIndex = currentIndex; root.refresh() } }
                        AppTextField { id: lineDate; text: Qt.formatDate(new Date(), "yyyy-MM-dd"); Layout.preferredWidth: 140 }
                        AppTextField { id: lineLabel; placeholderText: "Libellé du relevé"; Layout.fillWidth: true }
                        AppTextField { id: lineAmount; placeholderText: "Montant (+/-)"; Layout.preferredWidth: 130 }
                        AppButton {
                            text: "Ajouter la ligne"
                            onClicked: if (accountBox.currentIndex >= 0) school.addBankLine({accountId: accountRows[accountBox.currentIndex].id, date: lineDate.text,
                                                                                            label: lineLabel.text, amount: parseFloat(lineAmount.text.replace(",", ".")) || 0})
                        }
                    }
                    Repeater {
                        model: root.lineRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.lineDate; Layout.preferredWidth: 110 }
                            Label { text: modelData.label; Layout.fillWidth: true }
                            Label { text: root.fmt(modelData.amount); font.bold: true }
                            ComboBox {
                                id: matchBox
                                visible: modelData.paymentId === 0
                                Layout.preferredWidth: 260
                                model: root.unreconciled
                                textRole: "label"
                                valueRole: "id"
                            }
                            AppButton {
                                visible: modelData.paymentId === 0
                                text: "Rapprocher"
                                onClicked: school.reconcileBankLine(modelData.id, matchBox.currentValue)
                            }
                            Label { visible: modelData.paymentId > 0; text: "✔ rapprochée"; color: "#0F9D8F" }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: methodColumn.implicitHeight + 40
                ColumnLayout {
                    id: methodColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Moyens de paiement"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.methodRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.label; Layout.fillWidth: true }
                            Label { text: modelData.active ? "Actif" : "Désactivé"; color: modelData.active ? "#0F9D8F" : "#C62828" }
                            AppButton { text: modelData.active ? "Désactiver" : "Activer"; onClicked: school.setPaymentMethodActive(modelData.code, !modelData.active) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: methodCode; placeholderText: "Code (ex. wave)"; Layout.preferredWidth: 160 }
                        AppTextField { id: methodLabel; placeholderText: "Libellé (ex. Wave)"; Layout.fillWidth: true }
                        AppButton { text: "Ajouter"; highlighted: true; onClicked: if (school.addPaymentMethod(methodCode.text, methodLabel.text)) { methodCode.text = ""; methodLabel.text = "" } }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: scheduleColumn.implicitHeight + 40
                ColumnLayout {
                    id: scheduleColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Échéanciers de paiement"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Le statut est calculé : une échéance est « payée » quand les paiements de l'élève couvrent les échéances précédentes et celle-ci."; color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    ComboBox {
                        id: studentBox
                        Layout.fillWidth: true
                        model: root.studentOptions
                        textRole: "label"
                        valueRole: "id"
                        onCurrentValueChanged: root.refreshSchedule()
                    }
                    Repeater {
                        model: root.scheduleRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.dueDate; Layout.preferredWidth: 110 }
                            Label { text: modelData.label; Layout.fillWidth: true }
                            Label { text: root.fmt(modelData.amount); font.bold: true }
                            Label { text: modelData.status === "paid" ? "Payée" : modelData.status === "partial" ? "Partielle" : "À payer"
                                    color: modelData.status === "paid" ? "#0F9D8F" : modelData.status === "partial" ? "#B7791F" : "#C62828" }
                            AppButton { text: "Supprimer"; onClicked: school.deleteScheduleInstallment(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: schedLabel; placeholderText: "Libellé (ex. 1re tranche)"; Layout.fillWidth: true }
                        AppTextField { id: schedDate; placeholderText: "Échéance AAAA-MM-JJ"; Layout.preferredWidth: 160 }
                        AppTextField { id: schedAmount; placeholderText: "Montant"; Layout.preferredWidth: 130; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Ajouter l'échéance"; highlighted: true
                            onClicked: if (school.addScheduleInstallment(studentBox.currentValue, schedLabel.text, schedDate.text, parseFloat(schedAmount.text.replace(",", ".")) || 0)) { schedLabel.text = ""; schedDate.text = ""; schedAmount.text = "" }
                        }
                    }
                }
            }
        }
    }
}
