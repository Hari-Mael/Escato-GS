#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-ressources-humaines main
git rm -q --ignore-unmatch install-phase*.sh || true

cat > qml/pages/HrPage.qml <<'QML'
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
QML

python3 <<'PY'
def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

ROLES = ["administrateur", "enseignant", "eleve", "parent", "comptable"]
PERMS = [
    ("hr.manage", "Gérer les salariés, présences et congés", "Ressources humaines", ["administrateur"]),
    ("hr.payroll", "Gérer avances, primes, retenues et paie", "Ressources humaines", ["administrateur", "comptable"]),
]

db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS hr_departments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
        ))",

        R"(CREATE TABLE IF NOT EXISTS hr_positions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
        ))",

        R"(CREATE TABLE IF NOT EXISTS hr_employees(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            full_name TEXT NOT NULL,
            phone TEXT,
            department_id INTEGER REFERENCES hr_departments(id) ON DELETE SET NULL,
            position_id INTEGER REFERENCES hr_positions(id) ON DELETE SET NULL,
            contract_type TEXT,
            start_date TEXT,
            base_salary REAL NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'actif' CHECK(status IN ('actif','sorti'))
        ))",

        R"(CREATE TABLE IF NOT EXISTS hr_attendance(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_id INTEGER NOT NULL REFERENCES hr_employees(id) ON DELETE CASCADE,
            day TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('present','absent','late','leave')),
            UNIQUE(employee_id, day)
        ))",

        R"(CREATE TABLE IF NOT EXISTS hr_leaves(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_id INTEGER NOT NULL REFERENCES hr_employees(id) ON DELETE CASCADE,
            kind TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'en attente'
        ))",

        R"(CREATE TABLE IF NOT EXISTS hr_advances(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_id INTEGER NOT NULL REFERENCES hr_employees(id) ON DELETE CASCADE,
            advance_date TEXT NOT NULL,
            amount REAL NOT NULL,
            deducted INTEGER NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS hr_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_id INTEGER NOT NULL REFERENCES hr_employees(id) ON DELETE CASCADE,
            period TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('prime','retenue')),
            label TEXT NOT NULL,
            amount REAL NOT NULL
        ))",

        R"(CREATE TABLE IF NOT EXISTS payroll_runs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            period TEXT NOT NULL,
            employee_id INTEGER NOT NULL REFERENCES hr_employees(id) ON DELETE CASCADE,
            gross REAL NOT NULL,
            social REAL NOT NULL,
            advances REAL NOT NULL,
            net REAL NOT NULL,
            employer_cost REAL NOT NULL,
            UNIQUE(period, employee_id)
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')
seed = []
for key, label, group, roles in PERMS:
    seed.append('    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES(\'%s\',\'%s\',\'%s\')")) return false;' % (key, label.replace("'", "''"), group))
    vals = ",".join("('%s','%s',%d)" % (r, key, 1 if r in roles else 0) for r in ROLES)
    seed.append('    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES %s")) return false;' % vals)
edit(db, 'bool Database::seed()\n{\n', 'bool Database::seed()\n{\n' + "\n".join(seed) + "\n\n")

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QVariantList auditLogs(int limit) const;\n', '''    Q_INVOKABLE QVariantList auditLogs(int limit) const;

    Q_INVOKABLE QVariantList hrDepartments() const;
    Q_INVOKABLE bool addHrDepartment(const QString &name);
    Q_INVOKABLE QVariantList hrPositions() const;
    Q_INVOKABLE bool addHrPosition(const QString &name);
    Q_INVOKABLE QVariantList hrEmployees() const;
    Q_INVOKABLE bool addHrEmployee(const QVariantMap &v);
    Q_INVOKABLE bool setHrEmployeeStatus(int id, const QString &status);
    Q_INVOKABLE QVariantList hrAttendanceFor(const QString &day) const;
    Q_INVOKABLE bool setHrAttendance(int employeeId, const QString &day, const QString &status);
    Q_INVOKABLE QVariantList hrLeaves() const;
    Q_INVOKABLE bool addHrLeave(const QVariantMap &v);
    Q_INVOKABLE bool decideHrLeave(int id, bool approve);
    Q_INVOKABLE QVariantList hrAdvances() const;
    Q_INVOKABLE bool addHrAdvance(const QVariantMap &v);
    Q_INVOKABLE QVariantList hrItems(const QString &period) const;
    Q_INVOKABLE bool addHrItem(const QVariantMap &v);
    Q_INVOKABLE QVariantMap hrSocialSettings() const;
    Q_INVOKABLE bool saveHrSocialSettings(double employeeRate, double employerRate);
    Q_INVOKABLE QVariantList hrPayrollPreview(const QString &period) const;
    Q_INVOKABLE bool validateHrPayroll(const QString &period);
    Q_INVOKABLE QVariantMap hrDashboard() const;
    Q_INVOKABLE QVariantList hrHistory(int limit) const;
''')

cpp = 'src/core/SchoolApp.cpp'
s = open(cpp, encoding='utf-8').read()
s += '''
namespace {
QDate hrPeriodEnd(const QString &period)
{
    const QDate first = QDate::fromString(period + "-01", "yyyy-MM-dd");
    return first.isValid() ? first.addMonths(1).addDays(-1) : QDate();
}
}

QVariantList SchoolApp::hrDepartments() const
{
    QVariantList out;
    if (!can("hr.manage") && !can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name FROM hr_departments ORDER BY name")) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); out << m; }
    return out;
}

bool SchoolApp::addHrDepartment(const QString &name)
{
    if (!can("hr.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty()) { emit errorOccurred(QStringLiteral("Nom du service requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_departments(name) VALUES(?)");
    q.addBindValue(n);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce service existe déjà.") : q.lastError().text()); return false; }
    audit("create", "hr_department", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrPositions() const
{
    QVariantList out;
    if (!can("hr.manage") && !can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name FROM hr_positions ORDER BY name")) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); out << m; }
    return out;
}

bool SchoolApp::addHrPosition(const QString &name)
{
    if (!can("hr.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty()) { emit errorOccurred(QStringLiteral("Nom du poste requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_positions(name) VALUES(?)");
    q.addBindValue(n);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce poste existe déjà.") : q.lastError().text()); return false; }
    audit("create", "hr_position", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrEmployees() const
{
    QVariantList out;
    if (!can("hr.manage") && !can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT e.id,e.full_name,COALESCE(e.phone,''),COALESCE(d.name,''),COALESCE(p.name,''),COALESCE(e.contract_type,''),"
                "COALESCE(e.start_date,''),e.base_salary,e.status FROM hr_employees e "
                "LEFT JOIN hr_departments d ON d.id=e.department_id LEFT JOIN hr_positions p ON p.id=e.position_id ORDER BY e.full_name")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["phone"] = q.value(2).toString();
        m["department"] = q.value(3).toString();
        m["position"] = q.value(4).toString();
        m["contract"] = q.value(5).toString();
        m["startDate"] = q.value(6).toString();
        m["baseSalary"] = q.value(7).toDouble();
        m["status"] = q.value(8).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addHrEmployee(const QVariantMap &v)
{
    if (!can("hr.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const double base = v.value("baseSalary").toDouble();
    const QString start = v.value("startDate").toString().trimmed();
    if (name.isEmpty() || base < 0 || (!start.isEmpty() && !QDate::fromString(start, "yyyy-MM-dd").isValid())) {
        emit errorOccurred(QStringLiteral("Nom, salaire de base (≥ 0) et date de début (AAAA-MM-JJ) valides requis."));
        return false;
    }
    const int dep = v.value("departmentId").toInt();
    const int pos = v.value("positionId").toInt();
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_employees(full_name,phone,department_id,position_id,contract_type,start_date,base_salary) VALUES(?,?,?,?,?,?,?)");
    q.addBindValue(name);
    q.addBindValue(v.value("phone").toString().trimmed());
    q.addBindValue(dep > 0 ? QVariant(dep) : QVariant());
    q.addBindValue(pos > 0 ? QVariant(pos) : QVariant());
    q.addBindValue(v.value("contractType").toString().trimmed());
    q.addBindValue(start.isEmpty() ? QVariant() : QVariant(start));
    q.addBindValue(base);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "hr_employee", q.lastInsertId().toInt(), name);
    emit dataChanged();
    return true;
}

bool SchoolApp::setHrEmployeeStatus(int id, const QString &status)
{
    if (!can("hr.manage")) return false;
    if (!QStringList({"actif", "sorti"}).contains(status)) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE hr_employees SET status=? WHERE id=?");
    q.addBindValue(status);
    q.addBindValue(id);
    if (!q.exec() || q.numRowsAffected() != 1) return false;
    audit("update", "hr_employee", id, status);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrAttendanceFor(const QString &day) const
{
    QVariantList out;
    if (!can("hr.manage")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT e.id,e.full_name,COALESCE(a.status,'present') FROM hr_employees e "
              "LEFT JOIN hr_attendance a ON a.employee_id=e.id AND a.day=? WHERE e.status='actif' ORDER BY e.full_name");
    q.addBindValue(day.trimmed());
    if (!q.exec()) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); m["status"] = q.value(2).toString(); out << m; }
    return out;
}

bool SchoolApp::setHrAttendance(int employeeId, const QString &day, const QString &status)
{
    if (!can("hr.manage")) return false;
    if (!QDate::fromString(day, "yyyy-MM-dd").isValid() || !QStringList({"present", "absent", "late", "leave"}).contains(status)) return false;
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_attendance(employee_id,day,status) VALUES(?,?,?) ON CONFLICT(employee_id,day) DO UPDATE SET status=excluded.status");
    q.addBindValue(employeeId);
    q.addBindValue(day);
    q.addBindValue(status);
    if (!q.exec()) return false;
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrLeaves() const
{
    QVariantList out;
    if (!can("hr.manage")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT l.id,e.full_name,l.kind,l.start_date,l.end_date,l.status FROM hr_leaves l "
                "JOIN hr_employees e ON e.id=l.employee_id ORDER BY l.id DESC LIMIT 200")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["kind"] = q.value(2).toString();
        m["startDate"] = q.value(3).toString();
        m["endDate"] = q.value(4).toString();
        m["status"] = q.value(5).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addHrLeave(const QVariantMap &v)
{
    if (!can("hr.manage")) return false;
    const QDate s = QDate::fromString(v.value("startDate").toString(), "yyyy-MM-dd");
    const QDate e = QDate::fromString(v.value("endDate").toString(), "yyyy-MM-dd");
    const QString kind = v.value("kind").toString().trimmed();
    if (v.value("employeeId").toInt() <= 0 || kind.isEmpty() || !s.isValid() || !e.isValid() || e < s) {
        emit errorOccurred(QStringLiteral("Salarié, type et dates valides (AAAA-MM-JJ, fin après début) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_leaves(employee_id,kind,start_date,end_date) VALUES(?,?,?,?)");
    q.addBindValue(v.value("employeeId").toInt());
    q.addBindValue(kind);
    q.addBindValue(s.toString("yyyy-MM-dd"));
    q.addBindValue(e.toString("yyyy-MM-dd"));
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "hr_leave", q.lastInsertId().toInt(), kind);
    emit dataChanged();
    return true;
}

bool SchoolApp::decideHrLeave(int id, bool approve)
{
    if (!can("hr.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE hr_leaves SET status=? WHERE id=? AND status='en attente'");
    q.addBindValue(approve ? QStringLiteral("approuvé") : QStringLiteral("refusé"));
    q.addBindValue(id);
    if (!q.exec() || q.numRowsAffected() != 1) return false;
    audit(approve ? "approve" : "refuse", "hr_leave", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrAdvances() const
{
    QVariantList out;
    if (!can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT a.id,e.full_name,a.advance_date,a.amount,a.deducted FROM hr_advances a "
                "JOIN hr_employees e ON e.id=a.employee_id ORDER BY a.id DESC LIMIT 200")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["date"] = q.value(2).toString();
        m["amount"] = q.value(3).toDouble();
        m["deducted"] = q.value(4).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addHrAdvance(const QVariantMap &v)
{
    if (!can("hr.payroll")) return false;
    const QDate d = QDate::fromString(v.value("date").toString(), "yyyy-MM-dd");
    const double amount = v.value("amount").toDouble();
    if (v.value("employeeId").toInt() <= 0 || !d.isValid() || amount <= 0) {
        emit errorOccurred(QStringLiteral("Salarié, date et montant (> 0) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_advances(employee_id,advance_date,amount) VALUES(?,?,?)");
    q.addBindValue(v.value("employeeId").toInt());
    q.addBindValue(d.toString("yyyy-MM-dd"));
    q.addBindValue(amount);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "hr_advance", q.lastInsertId().toInt(), QString::number(amount, 'f', 0));
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrItems(const QString &period) const
{
    QVariantList out;
    if (!can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT i.id,e.full_name,i.kind,i.label,i.amount FROM hr_items i JOIN hr_employees e ON e.id=i.employee_id "
              "WHERE i.period=? ORDER BY e.full_name");
    q.addBindValue(period.trimmed());
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["kind"] = q.value(2).toString();
        m["label"] = q.value(3).toString();
        m["amount"] = q.value(4).toDouble();
        out << m;
    }
    return out;
}

bool SchoolApp::addHrItem(const QVariantMap &v)
{
    if (!can("hr.payroll")) return false;
    const QString period = v.value("period").toString().trimmed();
    const QString kind = v.value("kind").toString();
    const QString label = v.value("label").toString().trimmed();
    const double amount = v.value("amount").toDouble();
    if (v.value("employeeId").toInt() <= 0 || !hrPeriodEnd(period).isValid() || !QStringList({"prime", "retenue"}).contains(kind)
        || label.isEmpty() || amount <= 0) {
        emit errorOccurred(QStringLiteral("Salarié, période (AAAA-MM), type, libellé et montant (> 0) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_items(employee_id,period,kind,label,amount) VALUES(?,?,?,?,?)");
    q.addBindValue(v.value("employeeId").toInt());
    q.addBindValue(period);
    q.addBindValue(kind);
    q.addBindValue(label);
    q.addBindValue(amount);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "hr_item", q.lastInsertId().toInt(), kind + " " + label);
    emit dataChanged();
    return true;
}

QVariantMap SchoolApp::hrSocialSettings() const
{
    QVariantMap out;
    if (!can("hr.payroll")) return out;
    out["employeeRate"] = setting("hr_employee_rate").isEmpty() ? 0.0 : setting("hr_employee_rate").toDouble();
    out["employerRate"] = setting("hr_employer_rate").isEmpty() ? 0.0 : setting("hr_employer_rate").toDouble();
    return out;
}

bool SchoolApp::saveHrSocialSettings(double employeeRate, double employerRate)
{
    if (!can("hr.payroll")) return false;
    if (employeeRate < 0 || employeeRate > 100 || employerRate < 0 || employerRate > 100) {
        emit errorOccurred(QStringLiteral("Taux entre 0 et 100 %."));
        return false;
    }
    setSetting("hr_employee_rate", QString::number(employeeRate));
    setSetting("hr_employer_rate", QString::number(employerRate));
    return true;
}

QVariantList SchoolApp::hrPayrollPreview(const QString &period) const
{
    QVariantList out;
    if (!can("hr.payroll")) return out;
    const QDate end = hrPeriodEnd(period.trimmed());
    if (!end.isValid()) return out;
    const double empRate = setting("hr_employee_rate").isEmpty() ? 0.0 : setting("hr_employee_rate").toDouble();
    const double erRate = setting("hr_employer_rate").isEmpty() ? 0.0 : setting("hr_employer_rate").toDouble();
    const QString p = period.trimmed();
    QSqlQuery emps(m_db.db());
    if (!emps.exec("SELECT id,full_name,base_salary FROM hr_employees WHERE status='actif' ORDER BY full_name")) return out;
    while (emps.next()) {
        const int eid = emps.value(0).toInt();
        const double base = emps.value(2).toDouble();
        QSqlQuery it(m_db.db());
        it.prepare("SELECT COALESCE(SUM(CASE WHEN kind='prime' THEN amount ELSE 0 END),0), COALESCE(SUM(CASE WHEN kind='retenue' THEN amount ELSE 0 END),0) "
                   "FROM hr_items WHERE employee_id=? AND period=?");
        it.addBindValue(eid);
        it.addBindValue(p);
        double primes = 0, retenues = 0;
        if (it.exec() && it.next()) { primes = it.value(0).toDouble(); retenues = it.value(1).toDouble(); }
        QSqlQuery adv(m_db.db());
        adv.prepare("SELECT COALESCE(SUM(amount),0) FROM hr_advances WHERE employee_id=? AND deducted=0 AND advance_date<=?");
        adv.addBindValue(eid);
        adv.addBindValue(end.toString("yyyy-MM-dd"));
        const double advances = adv.exec() && adv.next() ? adv.value(0).toDouble() : 0.0;
        const double gross = base + primes - retenues;
        const double social = gross * empRate / 100.0;
        QVariantMap m;
        m["employeeId"] = eid;
        m["name"] = emps.value(1).toString();
        m["base"] = base;
        m["primes"] = primes;
        m["retenues"] = retenues;
        m["gross"] = gross;
        m["social"] = social;
        m["advances"] = advances;
        m["net"] = gross - social - advances;
        m["employerCost"] = gross * (1.0 + erRate / 100.0);
        out << m;
    }
    return out;
}

bool SchoolApp::validateHrPayroll(const QString &period)
{
    if (!can("hr.payroll")) return false;
    const QString p = period.trimmed();
    const QDate end = hrPeriodEnd(p);
    if (!end.isValid()) { emit errorOccurred(QStringLiteral("Période au format AAAA-MM requise.")); return false; }
    QSqlQuery exists(m_db.db());
    exists.prepare("SELECT COUNT(*) FROM payroll_runs WHERE period=?");
    exists.addBindValue(p);
    if (exists.exec() && exists.next() && exists.value(0).toInt() > 0) {
        emit errorOccurred(QStringLiteral("La paie de cette période est déjà validée."));
        return false;
    }
    const QVariantList rows = hrPayrollPreview(p);
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    for (const QVariant &v : rows) {
        const QVariantMap m = v.toMap();
        QSqlQuery ins(db);
        ins.prepare("INSERT INTO payroll_runs(period,employee_id,gross,social,advances,net,employer_cost) VALUES(?,?,?,?,?,?,?)");
        ins.addBindValue(p);
        ins.addBindValue(m["employeeId"].toInt());
        ins.addBindValue(m["gross"].toDouble());
        ins.addBindValue(m["social"].toDouble());
        ins.addBindValue(m["advances"].toDouble());
        ins.addBindValue(m["net"].toDouble());
        ins.addBindValue(m["employerCost"].toDouble());
        if (!ins.exec()) { db.rollback(); emit errorOccurred(ins.lastError().text()); return false; }
        QSqlQuery ded(db);
        ded.prepare("UPDATE hr_advances SET deducted=1 WHERE employee_id=? AND deducted=0 AND advance_date<=?");
        ded.addBindValue(m["employeeId"].toInt());
        ded.addBindValue(end.toString("yyyy-MM-dd"));
        if (!ded.exec()) { db.rollback(); return false; }
    }
    db.commit();
    audit("validate", "hr_payroll", 0, p + " (" + QString::number(rows.size()) + " salariés)");
    emit dataChanged();
    return true;
}

QVariantMap SchoolApp::hrDashboard() const
{
    QVariantMap out;
    if (!can("hr.manage") && !can("hr.payroll")) return out;
    QSqlQuery a(m_db.db());
    a.exec("SELECT COUNT(*) FROM hr_employees WHERE status='actif'");
    out["activeEmployees"] = a.next() ? a.value(0).toInt() : 0;
    QSqlQuery l(m_db.db());
    l.exec("SELECT COUNT(*) FROM hr_leaves WHERE status='en attente'");
    out["pendingLeaves"] = l.next() ? l.value(0).toInt() : 0;
    QSqlQuery pr(m_db.db());
    pr.prepare("SELECT COUNT(*) FROM hr_attendance WHERE day=? AND status IN ('present','late')");
    pr.addBindValue(QDate::currentDate().toString("yyyy-MM-dd"));
    out["presentToday"] = pr.exec() && pr.next() ? pr.value(0).toInt() : 0;
    QSqlQuery vp(m_db.db());
    vp.exec("SELECT COUNT(DISTINCT period) FROM payroll_runs");
    out["validatedPeriods"] = vp.next() ? vp.value(0).toInt() : 0;
    return out;
}

QVariantList SchoolApp::hrHistory(int limit) const
{
    QVariantList out;
    if (!can("hr.manage") && !can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT a.created_at,COALESCE(u.name,'Système'),a.action,a.details FROM audit_logs a "
              "LEFT JOIN users u ON u.id=a.user_id WHERE a.entity LIKE 'hr_%' ORDER BY a.id DESC LIMIT ?");
    q.addBindValue(limit > 0 ? limit : 200);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["createdAt"] = q.value(0).toString();
        m["user"] = q.value(1).toString();
        m["action"] = q.value(2).toString();
        m["details"] = q.value(3).toString();
        out << m;
    }
    return out;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sb = 'qml/components/Sidebar.qml'
edit(sb, '                ["email", "Rapports par e-mail", "✉"],\n',
     '                ["email", "Rapports par e-mail", "✉"],\n                ["hr", "Ressources humaines", "👥"],\n')
mq = 'qml/Main.qml'
edit(mq, '"email":26}', '"email":26,"hr":27}')
edit(mq, '                        EmailPage {}\n', '                        EmailPage {}\n                        HrPage {}\n')
cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/EmailPage.qml\n', '        qml/pages/EmailPage.qml\n        qml/pages/HrPage.qml\n')
print("phase 17 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: ressources humaines (services, postes, salariés, présences, congés, avances, primes et retenues, paie, historique)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-ressources-humaines."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-ressources-humaines"
