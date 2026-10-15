import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property bool canHr: false
    property bool canPayroll: false
    property var employeeRows: []
    property var employeeOptions: []
    property var departmentRows: []
    property var positionRows: []
    property var leaveRows: []
    property var attendanceRows: []
    property var advanceRows: []
    property var itemRows: []
    property var previewRows: []
    property var historyRows: []
    property var dashboard: ({})
    property int sectionIndex: 0
    readonly property var sectionNames: ["Tableau RH", "Salariés", "Présences et congés", "Avances, primes et retenues", "Paie", "Historique RH"]
    readonly property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")

    function fmt(n) { return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar" }
    function refreshPerms() {
        canHr = school.can("hr.manage")
        canPayroll = school.can("hr.payroll")
    }
    function refresh() {
        refreshPerms()
        if (!canHr && !canPayroll) return
        employeeRows = school.hrEmployees()
        employeeOptions = employeeRows.map(function(e) { return {id: e.id, label: e.name + " (" + e.status + ")"} })
        departmentRows = school.hrDepartments()
        positionRows = school.hrPositions()
        leaveRows = school.hrLeaves()
        attendanceRows = school.hrAttendanceFor(attDay.text)
        advanceRows = school.hrAdvances()
        itemRows = school.hrItems(periodField.text)
        previewRows = school.hrPayrollPreview(periodField.text)
        historyRows = school.hrHistory(200)
        dashboard = school.hrDashboard()
        var s = school.hrSocialSettings()
        if (s.employeeRate !== undefined) { empRate.text = String(s.employeeRate); erRate.text = String(s.employerRate) }
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Label { text: "Ressources humaines"; font.pixelSize: 28; font.bold: true; Layout.fillWidth: true }
            ComboBox { id: sectionBox; Layout.preferredWidth: 260; model: root.sectionNames; onCurrentIndexChanged: root.sectionIndex = currentIndex }
        }

        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: root.sectionIndex

            ScrollView {
                clip: true
                ColumnLayout {
                    width: parent.width; spacing: 12
                    Label { text: "Tableau RH"; font.pixelSize: 18; font.bold: true }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 15
                        StatCard { title: "Salariés actifs"; value: String(root.dashboard.activeEmployees || 0) }
                        StatCard { title: "Congés en attente"; value: String(root.dashboard.pendingLeaves || 0) }
                        StatCard { title: "Présents aujourd'hui"; value: String(root.dashboard.presentToday || 0) }
                        StatCard { title: "Paies validées"; value: String(root.dashboard.validatedPeriods || 0) }
                    }
                }
            }

            ScrollView {
                clip: true
                ColumnLayout {
                    width: parent.width; spacing: 10
                    Label { text: "Services et postes"; font.pixelSize: 18; font.bold: true }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: depName; placeholderText: "Nouveau service"; Layout.fillWidth: true }
                        AppButton { text: "Ajouter le service"; visible: root.canHr; onClicked: if (school.addHrDepartment(depName.text)) depName.text = "" }
                        AppTextField { id: posName; placeholderText: "Nouveau poste"; Layout.fillWidth: true }
                        AppButton { text: "Ajouter le poste"; visible: root.canHr; onClicked: if (school.addHrPosition(posName.text)) posName.text = "" }
                    }
                    Label { text: "Salariés"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.employeeRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; font.bold: true; Layout.preferredWidth: 220 }
                            Label { text: modelData.department + " · " + modelData.position; color: "#667085"; Layout.fillWidth: true }
                            Label { text: root.fmt(modelData.baseSalary); font.bold: true }
                            Label { text: modelData.status; color: modelData.status === "actif" ? "#0F9D8F" : "#667085" }
                            AppButton { visible: root.canHr; text: modelData.status === "actif" ? "Marquer sorti" : "Réactiver"
                                onClicked: school.setHrEmployeeStatus(modelData.id, modelData.status === "actif" ? "sorti" : "actif") }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canHr
                        AppTextField { id: eName; placeholderText: "Nom complet"; Layout.fillWidth: true }
                        AppTextField { id: ePhone; placeholderText: "Téléphone"; Layout.preferredWidth: 130 }
                        ComboBox { id: eDep; Layout.preferredWidth: 160; model: root.departmentRows; textRole: "name"; valueRole: "id" }
                        ComboBox { id: ePos; Layout.preferredWidth: 160; model: root.positionRows; textRole: "name"; valueRole: "id" }
                        AppTextField { id: eContract; placeholderText: "Contrat (CDI, CDD…)"; Layout.preferredWidth: 150 }
                        AppTextField { id: eStart; placeholderText: "Début AAAA-MM-JJ"; Layout.preferredWidth: 150 }
                        AppTextField { id: eSalary; placeholderText: "Salaire de base"; Layout.preferredWidth: 150; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: if (school.addHrEmployee({name: eName.text, phone: ePhone.text, departmentId: eDep.currentValue, positionId: ePos.currentValue,
                                                                 contractType: eContract.text, startDate: eStart.text,
                                                                 baseSalary: parseFloat(eSalary.text.replace(",", ".")) || 0})) { eName.text = ""; eSalary.text = "" }
                        }
                    }
                }
            }

            ScrollView {
                clip: true
                ColumnLayout {
                    width: parent.width; spacing: 10
                    Label { text: "Présences du personnel"; font.pixelSize: 18; font.bold: true }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: attDay; text: root.today; Layout.preferredWidth: 150; onTextChanged: root.refresh() }
                        Label { text: "(date AAAA-MM-JJ)"; color: "#667085" }
                    }
                    Repeater {
                        model: root.attendanceRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.fillWidth: true }
                            ComboBox {
                                Layout.preferredWidth: 160
                                model: ["Présent", "Absent", "Retard", "En congé"]
                                currentIndex: ["present", "absent", "late", "leave"].indexOf(modelData.status) < 0 ? 0 : ["present", "absent", "late", "leave"].indexOf(modelData.status)
                                onActivated: function(i) { school.setHrAttendance(modelData.id, attDay.text, ["present", "absent", "late", "leave"][i]) }
                            }
                        }
                    }
                    Label { text: "Demandes de congés et absences"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.leaveRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.preferredWidth: 200 }
                            Label { text: modelData.kind + " · " + modelData.startDate + " → " + modelData.endDate; color: "#667085"; Layout.fillWidth: true }
                            Label { text: modelData.status; font.bold: true; color: modelData.status === "approuvé" ? "#0F9D8F" : modelData.status === "refusé" ? "#C62828" : "#B7791F" }
                            AppButton { visible: root.canHr && modelData.status === "en attente"; text: "Approuver"; onClicked: school.decideHrLeave(modelData.id, true) }
                            AppButton { visible: root.canHr && modelData.status === "en attente"; text: "Refuser"; onClicked: school.decideHrLeave(modelData.id, false) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canHr
                        ComboBox { id: lvEmp; Layout.preferredWidth: 240; model: root.employeeOptions; textRole: "label"; valueRole: "id" }
                        AppTextField { id: lvKind; placeholderText: "Type (congé annuel, maladie…)"; Layout.preferredWidth: 200 }
                        AppTextField { id: lvStart; placeholderText: "Début AAAA-MM-JJ"; Layout.preferredWidth: 150 }
                        AppTextField { id: lvEnd; placeholderText: "Fin AAAA-MM-JJ"; Layout.preferredWidth: 150 }
                        AppButton { text: "Enregistrer la demande"; highlighted: true
                            onClicked: school.addHrLeave({employeeId: lvEmp.currentValue, kind: lvKind.text, startDate: lvStart.text, endDate: lvEnd.text}) }
                    }
                }
            }

            ScrollView {
                clip: true
                ColumnLayout {
                    width: parent.width; spacing: 10
                    Label { text: "Avances sur salaire"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.advanceRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.preferredWidth: 200 }
                            Label { text: modelData.date; color: "#667085"; Layout.preferredWidth: 110 }
                            Label { text: root.fmt(modelData.amount); font.bold: true; Layout.fillWidth: true }
                            Label { text: modelData.deducted ? "Déduite" : "À déduire"; color: modelData.deducted ? "#0F9D8F" : "#B7791F" }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canPayroll
                        ComboBox { id: avEmp; Layout.preferredWidth: 240; model: root.employeeOptions; textRole: "label"; valueRole: "id" }
                        AppTextField { id: avDate; text: root.today; Layout.preferredWidth: 140 }
                        AppTextField { id: avAmount; placeholderText: "Montant"; Layout.preferredWidth: 140; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton { text: "Enregistrer l'avance"; highlighted: true
                            onClicked: school.addHrAdvance({employeeId: avEmp.currentValue, date: avDate.text, amount: parseFloat(avAmount.text.replace(",", ".")) || 0}) }
                    }
                    Label { text: "Primes et retenues de la période"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.itemRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.preferredWidth: 200 }
                            Label { text: (modelData.kind === "prime" ? "Prime" : "Retenue") + " · " + modelData.label; color: "#667085"; Layout.fillWidth: true }
                            Label { text: root.fmt(modelData.amount); font.bold: true; color: modelData.kind === "prime" ? "#0F9D8F" : "#C62828" }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canPayroll
                        ComboBox { id: itEmp; Layout.preferredWidth: 240; model: root.employeeOptions; textRole: "label"; valueRole: "id" }
                        ComboBox { id: itKind; Layout.preferredWidth: 120; model: ["Prime", "Retenue"] }
                        AppTextField { id: itLabel; placeholderText: "Libellé"; Layout.preferredWidth: 180 }
                        AppTextField { id: itAmount; placeholderText: "Montant"; Layout.preferredWidth: 130; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton { text: "Ajouter"; highlighted: true
                            onClicked: school.addHrItem({employeeId: itEmp.currentValue, period: periodField.text, kind: itKind.currentIndex === 0 ? "prime" : "retenue",
                                                         label: itLabel.text, amount: parseFloat(itAmount.text.replace(",", ".")) || 0}) }
                    }
                }
            }

            ScrollView {
                clip: true
                ColumnLayout {
                    width: parent.width; spacing: 10
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Label { text: "Période (AAAA-MM)" }
                        AppTextField { id: periodField; text: root.today.substring(0, 7); Layout.preferredWidth: 130; onTextChanged: root.refresh() }
                        AppButton { text: "Valider la paie du mois"; highlighted: true; visible: root.canPayroll
                            onClicked: school.validateHrPayroll(periodField.text) }
                    }
                    Label {
                        text: "Taux de cotisations : à saisir à partir des barèmes officiels en vigueur. Aucun taux n'est fourni par défaut."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canPayroll
                        Label { text: "Part salarié (%)" }
                        AppTextField { id: empRate; Layout.preferredWidth: 100; inputMethodHints: Qt.ImhDigitsOnly }
                        Label { text: "Part employeur (%)" }
                        AppTextField { id: erRate; Layout.preferredWidth: 100; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton { text: "Enregistrer les taux"
                            onClicked: school.saveHrSocialSettings(parseFloat(empRate.text.replace(",", ".")) || 0, parseFloat(erRate.text.replace(",", ".")) || 0) }
                    }
                    Label { text: "Aperçu de la paie"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.previewRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.preferredWidth: 200 }
                            Label { text: "brut " + root.fmt(modelData.gross); Layout.preferredWidth: 170 }
                            Label { text: "cotis. " + root.fmt(modelData.social); color: "#667085"; Layout.preferredWidth: 150 }
                            Label { text: "avances " + root.fmt(modelData.advances); color: "#667085"; Layout.preferredWidth: 170 }
                            Label { text: "net " + root.fmt(modelData.net); font.bold: true; color: "#0F9D8F" }
                        }
                    }
                }
            }

            ScrollView {
                clip: true
                ColumnLayout {
                    width: parent.width; spacing: 6
                    Label { text: "Historique RH"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.historyRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.createdAt; color: "#667085"; Layout.preferredWidth: 150 }
                            Label { text: modelData.user; Layout.preferredWidth: 150; elide: Text.ElideRight }
                            Label { text: modelData.action; Layout.preferredWidth: 110 }
                            Label { text: modelData.details; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }
    }
}
