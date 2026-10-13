import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var tuitions: []
    property var overview: ({})
    property var studentRows: []
    property var feeTypes: []
    property bool canTuition: false
    property bool canOneTime: false

    function refreshPerms() {
        canTuition = school.can("fees.tuition")
        canOneTime = school.can("fees.onetime.manage")
    }

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function refreshTuitions() {
        tuitions = school.classTuitions()
    }
    function refreshOverview() {
        overview = school.balanceOverview(fromDate.text, toDate.text)
        studentRows = overview.students || []
    }
    function refreshFeeTypes() {
        feeTypes = school.feeTypes()
    }
    Component.onCompleted: { refreshPerms(); refreshTuitions(); refreshOverview(); refreshFeeTypes() }
    Connections {
        target: school
        function onDataChanged() { root.refreshPerms(); root.refreshTuitions(); root.refreshOverview(); root.refreshFeeTypes() }
        function onSessionChanged() { root.refreshPerms() }
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 18

            Label { text: "Frais et soldes"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: tuitionColumn.implicitHeight + 40

                ColumnLayout {
                    id: tuitionColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 8

                    Label { text: "Grille tarifaire mensuelle par classe"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Appliquée lors de la génération des factures mensuelles, pour les élèves qui n'ont pas de tarif individuel."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Repeater {
                        model: root.tuitions
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Label { text: modelData.className; Layout.preferredWidth: 150 }
                            AppTextField {
                                id: tuitionAmount
                                text: String(Math.round(modelData.monthlyAmount))
                                Layout.preferredWidth: 160
                                enabled: root.canTuition
                                inputMethodHints: Qt.ImhDigitsOnly
                            }
                            AppButton {
                                text: "Enregistrer"
                                visible: root.canTuition
                                onClicked: school.setClassTuition(modelData.className, parseFloat(tuitionAmount.text.replace(",", ".")) || 0)
                            }
                            Label { text: root.fmt(modelData.monthlyAmount); color: "#667085"; Layout.fillWidth: true }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: oneTimeColumn.implicitHeight + 40

                ColumnLayout {
                    id: oneTimeColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10

                    Label { text: "Frais ponctuels"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Inscription, uniforme, examen, carte scolaire… Un type de frais peut être assigné à toute une classe."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }

                    Repeater {
                        model: root.feeTypes
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.fillWidth: true }
                            Label { text: root.fmt(modelData.amount); color: "#667085" }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.canOneTime
                        spacing: 8
                        AppTextField { id: newFeeName; placeholderText: "Nouveau type (ex. Frais d'inscription)"; Layout.fillWidth: true }
                        AppTextField { id: newFeeAmount; placeholderText: "Montant par défaut"; Layout.preferredWidth: 170; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Ajouter le type"
                            highlighted: true
                            onClicked: {
                                if (school.addFeeType({name: newFeeName.text, amount: parseFloat(newFeeAmount.text.replace(",", ".")) || 0})) {
                                    newFeeName.text = ""; newFeeAmount.text = ""
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.canOneTime
                        spacing: 8
                        ComboBox {
                            id: assignType
                            Layout.preferredWidth: 220
                            model: root.feeTypes
                            textRole: "name"
                            valueRole: "id"
                        }
                        ComboBox {
                            id: assignClass
                            Layout.preferredWidth: 130
                            model: school.classes()
                        }
                        AppTextField { id: assignAmount; placeholderText: "Montant (Ar)"; Layout.preferredWidth: 140; inputMethodHints: Qt.ImhDigitsOnly }
                        AppTextField { id: assignDue; placeholderText: "Échéance AAAA-MM-JJ"; Layout.preferredWidth: 170 }
                        AppButton {
                            text: "Assigner à la classe"
                            highlighted: true
                            onClicked: school.assignOneTimeFeeToClass(assignType.currentValue, assignClass.currentText,
                                                                      parseFloat(assignAmount.text.replace(",", ".")) || 0, assignDue.text)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: overviewColumn.implicitHeight + 40

                ColumnLayout {
                    id: overviewColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 12

                    Label { text: "Vue d'ensemble des soldes"; font.pixelSize: 18; font.bold: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        AppTextField { id: fromDate; placeholderText: "Du AAAA-MM-JJ"; Layout.preferredWidth: 170 }
                        AppTextField { id: toDate; placeholderText: "Au AAAA-MM-JJ"; Layout.preferredWidth: 170 }
                        AppButton { text: "Actualiser"; highlighted: true; onClicked: root.refreshOverview() }
                        Label { text: "(vide = toutes les dates)"; color: "#667085" }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 15
                        StatCard { title: "Facturé"; value: root.fmt(root.overview.billed || 0) }
                        StatCard { title: "Encaissé"; value: root.fmt(root.overview.collected || 0) }
                        StatCard { title: "Reste à recouvrer"; value: root.fmt(root.overview.balance || 0) }
                        StatCard { title: "Factures en retard"; value: String(root.overview.lateCount || 0) }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Élève"; font.bold: true; color: "#667085"; Layout.fillWidth: true }
                        Label { text: "Classe"; font.bold: true; color: "#667085"; Layout.preferredWidth: 120 }
                        Label { text: "Facturé"; font.bold: true; color: "#667085"; Layout.preferredWidth: 130 }
                        Label { text: "Encaissé"; font.bold: true; color: "#667085"; Layout.preferredWidth: 130 }
                        Label { text: "Solde"; font.bold: true; color: "#667085"; Layout.preferredWidth: 130 }
                    }
                    Repeater {
                        model: root.studentRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: modelData.className; Layout.preferredWidth: 120 }
                            Label { text: root.fmt(modelData.billed); Layout.preferredWidth: 130 }
                            Label { text: root.fmt(modelData.collected); Layout.preferredWidth: 130 }
                            Label {
                                text: root.fmt(modelData.balance)
                                font.bold: true
                                color: modelData.balance > 0 ? "#C62828" : "#0F9D8F"
                                Layout.preferredWidth: 130
                            }
                        }
                    }
                }
            }
        }
    }
}
