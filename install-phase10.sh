#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-scolarite-pedagogie main
git rm -q --ignore-unmatch install-phase*.sh || true

cat > qml/pages/CurriculumPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var subjectRows: []
    property var assignmentRows: []
    property var slotRows: []
    property var teacherRows: []
    readonly property var dayNames: ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]

    function refresh() {
        subjectRows = school.subjects()
        teacherRows = school.users("enseignant")
        refreshClass()
    }
    function refreshClass() {
        if (!classBox.currentText) return
        assignmentRows = school.classAssignments(classBox.currentText)
        slotRows = school.timetableSlots(classBox.currentText)
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

            Label { text: "Matières, affectations et emploi du temps"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: subjectColumn.implicitHeight + 40
                ColumnLayout {
                    id: subjectColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Matières"; font.pixelSize: 18; font.bold: true }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: subjectName; placeholderText: "Nom de la matière"; Layout.fillWidth: true }
                        AppTextField { id: subjectCoef; placeholderText: "Coefficient"; Layout.preferredWidth: 130; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: {
                                if (school.addSubject({name: subjectName.text, coefficient: parseFloat(subjectCoef.text.replace(",", ".")) || 0})) {
                                    subjectName.text = ""; subjectCoef.text = ""
                                }
                            }
                        }
                    }
                    Repeater {
                        model: root.subjectRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.fillWidth: true }
                            Label { text: "coef. " + modelData.coefficient; color: "#667085" }
                            AppButton { text: "Supprimer"; onClicked: school.deleteSubject(modelData.id) }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: classColumn.implicitHeight + 40
                ColumnLayout {
                    id: classColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Classe"; font.pixelSize: 18; font.bold: true }
                        ComboBox {
                            id: classBox
                            Layout.preferredWidth: 200
                            model: school.classes()
                            onCurrentTextChanged: root.refreshClass()
                        }
                    }

                    Label { text: "Affectation des enseignants"; font.bold: true; color: "#0B2A43" }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        ComboBox { id: assignSubject; Layout.preferredWidth: 220; model: root.subjectRows; textRole: "name"; valueRole: "id" }
                        ComboBox { id: assignTeacher; Layout.preferredWidth: 240; model: root.teacherRows; textRole: "name"; valueRole: "id" }
                        AppButton {
                            text: "Affecter"; highlighted: true
                            onClicked: school.setClassAssignment(classBox.currentText, assignSubject.currentValue, assignTeacher.currentValue)
                        }
                    }
                    Repeater {
                        model: root.assignmentRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.subject; Layout.fillWidth: true }
                            Label { text: modelData.teacher; color: "#667085" }
                            AppButton { text: "Retirer"; onClicked: school.deleteClassAssignment(modelData.id) }
                        }
                    }

                    Label { text: "Emploi du temps"; font.bold: true; color: "#0B2A43" }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        ComboBox { id: slotDay; Layout.preferredWidth: 130; model: root.dayNames }
                        AppTextField { id: slotStart; text: "08:00"; Layout.preferredWidth: 90 }
                        AppTextField { id: slotEnd; text: "09:00"; Layout.preferredWidth: 90 }
                        ComboBox { id: slotSubject; Layout.preferredWidth: 180; model: root.subjectRows; textRole: "name"; valueRole: "id" }
                        AppTextField { id: slotRoom; placeholderText: "Salle"; Layout.preferredWidth: 110 }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: school.addTimetableSlot({className: classBox.currentText, weekday: slotDay.currentIndex + 1,
                                                                start: slotStart.text, end: slotEnd.text,
                                                                subjectId: slotSubject.currentValue, room: slotRoom.text})
                        }
                    }
                    Repeater {
                        model: root.slotRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: root.dayNames[modelData.weekday - 1]; Layout.preferredWidth: 110 }
                            Label { text: modelData.startTime + " – " + modelData.endTime; Layout.preferredWidth: 130 }
                            Label { text: modelData.subject; Layout.fillWidth: true }
                            Label { text: modelData.room; color: "#667085" }
                            AppButton { text: "Supprimer"; onClicked: school.deleteTimetableSlot(modelData.id) }
                        }
                    }
                }
            }
        }
    }
}
QML

cat > qml/pages/AttendancePage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var rows: []
    readonly property var statusLabels: ["Présent", "Absent", "Retard", "Excusé"]
    readonly property var statusCodes: ["present", "absent", "late", "excused"]

    function statusIndex(code) {
        var i = statusCodes.indexOf(code)
        return i < 0 ? 0 : i
    }
    function refresh() {
        if (!classBox.currentText || !dayField.text) { rows = []; return }
        rows = school.attendanceFor(classBox.currentText, dayField.text)
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Label { text: "Présences"; font.pixelSize: 28; font.bold: true }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            ComboBox { id: classBox; Layout.preferredWidth: 200; model: school.classes(); onCurrentTextChanged: root.refresh() }
            AppTextField { id: dayField; text: Qt.formatDate(new Date(), "yyyy-MM-dd"); Layout.preferredWidth: 170; onTextChanged: root.refresh() }
            Label { text: "(date AAAA-MM-JJ)"; color: "#667085" }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: "white"; border.color: "#E3E8EE"
            ListView {
                anchors.fill: parent; anchors.margins: 12; clip: true
                model: root.rows
                delegate: RowLayout {
                    width: ListView.view.width
                    height: 48
                    Label { text: modelData.name; Layout.fillWidth: true }
                    ComboBox {
                        Layout.preferredWidth: 160
                        model: root.statusLabels
                        currentIndex: root.statusIndex(modelData.status)
                        onActivated: function(index) { school.setAttendance(modelData.studentId, dayField.text, root.statusCodes[index]) }
                    }
                }
            }
        }
    }
}
QML

cat > qml/pages/DisciplinePage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var studentOptions: []
    property var incidentRows: []

    function refreshStudents() {
        studentOptions = school.students().map(function(s) {
            return {id: s.id, label: s.lastName + " " + s.firstName + " (" + s.className + ")"}
        })
    }
    function refreshIncidents() {
        var id = studentBox.currentValue
        incidentRows = id ? school.incidents(id) : []
    }
    Component.onCompleted: refreshStudents()
    Connections {
        target: school
        function onDataChanged() { root.refreshStudents(); root.refreshIncidents() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Label { text: "Discipline"; font.pixelSize: 28; font.bold: true }

        Rectangle {
            Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
            implicitHeight: formColumn.implicitHeight + 32
            ColumnLayout {
                id: formColumn
                x: 16; y: 16; width: parent.width - 32; spacing: 8
                ComboBox {
                    id: studentBox
                    Layout.fillWidth: true
                    model: root.studentOptions
                    textRole: "label"
                    valueRole: "id"
                    onCurrentValueChanged: root.refreshIncidents()
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    AppTextField { id: incDate; text: Qt.formatDate(new Date(), "yyyy-MM-dd"); Layout.preferredWidth: 150 }
                    AppTextField { id: incCategory; placeholderText: "Catégorie (ex. Comportement)"; Layout.preferredWidth: 220 }
                    AppTextField { id: incSanction; placeholderText: "Sanction (ex. Avertissement)"; Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    AppTextField { id: incDescription; placeholderText: "Description des faits"; Layout.fillWidth: true }
                    AppButton {
                        text: "Enregistrer l'incident"; highlighted: true
                        onClicked: {
                            if (school.addIncident({studentId: studentBox.currentValue, date: incDate.text,
                                                    category: incCategory.text, description: incDescription.text,
                                                    sanction: incSanction.text})) {
                                incCategory.text = ""; incDescription.text = ""; incSanction.text = ""
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: "white"; border.color: "#E3E8EE"
            ListView {
                anchors.fill: parent; anchors.margins: 12; clip: true
                model: root.incidentRows
                delegate: RowLayout {
                    width: ListView.view.width
                    Label { text: modelData.date; Layout.preferredWidth: 110 }
                    Label { text: modelData.category; Layout.preferredWidth: 180; font.bold: true }
                    Label { text: modelData.description; Layout.fillWidth: true; elide: Text.ElideRight }
                    Label { text: modelData.sanction; color: "#667085" }
                }
            }
        }
    }
}
QML

cat > qml/pages/CouncilPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var rows: []

    function refresh() {
        if (!classBox.currentText || !termBox.currentText) { rows = []; return }
        rows = school.deliberation(classBox.currentText, termBox.currentText)
    }
    function decisionColor(d) {
        if (d === "Admis") return "#0F9D8F"
        if (d === "Rattrapage") return "#B7791F"
        if (d === "Ajourné") return "#C62828"
        return "#667085"
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Label { text: "Délibérations"; font.pixelSize: 28; font.bold: true }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            ComboBox { id: classBox; Layout.preferredWidth: 200; model: school.classes(); onCurrentTextChanged: root.refresh() }
            ComboBox { id: termBox; Layout.preferredWidth: 170; model: school.terms(); onCurrentTextChanged: root.refresh() }
            Label { text: "Admis : moyenne ≥ 10 · Rattrapage : 8 à 10 · Ajourné : < 8"; color: "#667085" }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: "white"; border.color: "#E3E8EE"
            ListView {
                anchors.fill: parent; anchors.margins: 12; clip: true
                model: root.rows
                delegate: RowLayout {
                    width: ListView.view.width
                    height: 48
                    Label { text: modelData.name; Layout.fillWidth: true }
                    Label { text: modelData.average === "" ? "—" : Number(modelData.average).toFixed(2) + " / 20"; Layout.preferredWidth: 130 }
                    Label { text: modelData.decision; font.bold: true; color: root.decisionColor(modelData.decision); Layout.preferredWidth: 120 }
                    AppButton { text: "🧾 Livret"; onClicked: printer.printBulletin(modelData.studentId, termBox.currentText) }
                }
            }
        }
    }
}
QML

python3 <<'PY'
import re

def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

ROLES = ["administrateur", "enseignant", "eleve", "parent", "comptable"]
PERMS = [
    ("subjects.manage", "Gérer les matières", "Pédagogie", ["administrateur"]),
    ("assignments.manage", "Affecter les enseignants aux classes", "Pédagogie", ["administrateur"]),
    ("timetable.manage", "Gérer l'emploi du temps", "Pédagogie", ["administrateur"]),
    ("attendance.record", "Saisir les présences", "Vie scolaire", ["administrateur", "enseignant"]),
    ("discipline.record", "Enregistrer les incidents disciplinaires", "Vie scolaire", ["administrateur", "enseignant"]),
    ("deliberations.view", "Voir les délibérations", "Pédagogie", ["administrateur", "enseignant"]),
]

db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS subjects(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            coefficient REAL NOT NULL DEFAULT 1
        ))",

        R"(CREATE TABLE IF NOT EXISTS class_assignments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_name TEXT NOT NULL,
            subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
            teacher_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            UNIQUE(class_name, subject_id)
        ))",

        R"(CREATE TABLE IF NOT EXISTS timetable_slots(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_name TEXT NOT NULL,
            weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 6),
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            subject_id INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
            room TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS attendance(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            day TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('present','absent','late','excused')),
            UNIQUE(student_id, day)
        ))",

        R"(CREATE TABLE IF NOT EXISTS incidents(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            incident_date TEXT NOT NULL,
            category TEXT NOT NULL,
            description TEXT,
            sanction TEXT,
            recorded_by INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')

seed_lines = []
for key, label, group, roles in PERMS:
    seed_lines.append('    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES(\'%s\',\'%s\',\'%s\')")) return false;' % (key, label.replace("'", "''"), group))
    vals = ",".join("('%s','%s',%d)" % (r, key, 1 if r in roles else 0) for r in ROLES)
    seed_lines.append('    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES %s")) return false;' % vals)
edit(db, 'bool Database::seed()\n{\n', 'bool Database::seed()\n{\n' + "\n".join(seed_lines) + "\n\n")

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE int payOneTimeFee(int feeId, const QString &method, const QString &reference);\n',
     '''    Q_INVOKABLE int payOneTimeFee(int feeId, const QString &method, const QString &reference);

    Q_INVOKABLE QVariantList subjects() const;
    Q_INVOKABLE bool addSubject(const QVariantMap &v);
    Q_INVOKABLE bool deleteSubject(int id);
    Q_INVOKABLE QVariantList classAssignments(const QString &className) const;
    Q_INVOKABLE bool setClassAssignment(const QString &className, int subjectId, int teacherId);
    Q_INVOKABLE bool deleteClassAssignment(int id);
    Q_INVOKABLE QVariantList timetableSlots(const QString &className) const;
    Q_INVOKABLE bool addTimetableSlot(const QVariantMap &v);
    Q_INVOKABLE bool deleteTimetableSlot(int id);
    Q_INVOKABLE QVariantList attendanceFor(const QString &className, const QString &day) const;
    Q_INVOKABLE bool setAttendance(int studentId, const QString &day, const QString &status);
    Q_INVOKABLE QVariantList incidents(int studentId) const;
    Q_INVOKABLE bool addIncident(const QVariantMap &v);
    Q_INVOKABLE QVariantList deliberation(const QString &className, const QString &term) const;
''')

cpp = 'src/core/SchoolApp.cpp'
s = open(cpp, encoding='utf-8').read()
s += '''
QVariantList SchoolApp::subjects() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name,coefficient FROM subjects ORDER BY name")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["coefficient"] = q.value(2).toDouble();
        out << m;
    }
    return out;
}

bool SchoolApp::addSubject(const QVariantMap &v)
{
    if (!can("subjects.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const double coef = v.value("coefficient").toDouble();
    if (name.isEmpty() || coef <= 0) {
        emit errorOccurred(QStringLiteral("Nom et coefficient (> 0) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO subjects(name,coefficient) VALUES(?,?)");
    q.addBindValue(name);
    q.addBindValue(coef);
    if (!q.exec()) {
        emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette matière existe déjà.") : q.lastError().text());
        return false;
    }
    audit("create", "subject", q.lastInsertId().toInt(), name);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteSubject(int id)
{
    if (!can("subjects.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM subjects WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "subject", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::classAssignments(const QString &className) const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT a.id,a.class_name,s.id,s.name,COALESCE(u.id,0),COALESCE(u.name,'non affecté') "
              "FROM class_assignments a JOIN subjects s ON s.id=a.subject_id LEFT JOIN users u ON u.id=a.teacher_id "
              "WHERE a.class_name=? ORDER BY s.name");
    q.addBindValue(className);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["className"] = q.value(1).toString();
        m["subjectId"] = q.value(2).toInt();
        m["subject"] = q.value(3).toString();
        m["teacherId"] = q.value(4).toInt();
        m["teacher"] = q.value(5).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::setClassAssignment(const QString &className, int subjectId, int teacherId)
{
    if (!can("assignments.manage")) return false;
    if (!classes().contains(className) || subjectId <= 0) {
        emit errorOccurred(QStringLiteral("Classe et matière requises."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO class_assignments(class_name,subject_id,teacher_id) VALUES(?,?,?) "
              "ON CONFLICT(class_name,subject_id) DO UPDATE SET teacher_id=excluded.teacher_id");
    q.addBindValue(className);
    q.addBindValue(subjectId);
    q.addBindValue(teacherId > 0 ? QVariant(teacherId) : QVariant());
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("update", "assignment", subjectId, className);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteClassAssignment(int id)
{
    if (!can("assignments.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM class_assignments WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "assignment", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::timetableSlots(const QString &className) const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT t.id,t.weekday,t.start_time,t.end_time,COALESCE(s.name,''),COALESCE(t.room,'') "
              "FROM timetable_slots t LEFT JOIN subjects s ON s.id=t.subject_id WHERE t.class_name=? ORDER BY t.weekday,t.start_time");
    q.addBindValue(className);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["weekday"] = q.value(1).toInt();
        m["startTime"] = q.value(2).toString();
        m["endTime"] = q.value(3).toString();
        m["subject"] = q.value(4).toString();
        m["room"] = q.value(5).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addTimetableSlot(const QVariantMap &v)
{
    if (!can("timetable.manage")) return false;
    const QString className = v.value("className").toString();
    const int weekday = v.value("weekday").toInt();
    const QTime start = QTime::fromString(v.value("start").toString(), "HH:mm");
    const QTime end = QTime::fromString(v.value("end").toString(), "HH:mm");
    if (!classes().contains(className) || weekday < 1 || weekday > 6 || !start.isValid() || !end.isValid() || end <= start) {
        emit errorOccurred(QStringLiteral("Classe, jour (lundi à samedi) et horaires valides requis (HH:mm, fin après début)."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO timetable_slots(class_name,weekday,start_time,end_time,subject_id,room) VALUES(?,?,?,?,?,?)");
    q.addBindValue(className);
    q.addBindValue(weekday);
    q.addBindValue(start.toString("HH:mm"));
    q.addBindValue(end.toString("HH:mm"));
    const int subjectId = v.value("subjectId").toInt();
    q.addBindValue(subjectId > 0 ? QVariant(subjectId) : QVariant());
    q.addBindValue(v.value("room").toString().trimmed());
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "timetable_slot", q.lastInsertId().toInt(), className);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteTimetableSlot(int id)
{
    if (!can("timetable.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM timetable_slots WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "timetable_slot", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::attendanceFor(const QString &className, const QString &day) const
{
    QVariantList out;
    if (!can("attendance.record")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT s.id,s.last_name || ' ' || s.first_name,COALESCE(a.status,'present') FROM students s "
              "LEFT JOIN attendance a ON a.student_id=s.id AND a.day=? "
              "WHERE s.current_class=? AND s.deleted_at IS NULL AND s.graduated_at IS NULL ORDER BY s.last_name,s.first_name");
    q.addBindValue(day);
    q.addBindValue(className);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["studentId"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["status"] = q.value(2).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::setAttendance(int studentId, const QString &day, const QString &status)
{
    if (!can("attendance.record")) return false;
    if (!QDate::fromString(day, "yyyy-MM-dd").isValid()) return false;
    if (!QStringList({"present", "absent", "late", "excused"}).contains(status)) return false;
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO attendance(student_id,day,status) VALUES(?,?,?) "
              "ON CONFLICT(student_id,day) DO UPDATE SET status=excluded.status");
    q.addBindValue(studentId);
    q.addBindValue(day);
    q.addBindValue(status);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::incidents(int studentId) const
{
    QVariantList out;
    if (!canViewStudent(studentId)) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,incident_date,category,COALESCE(description,''),COALESCE(sanction,'') FROM incidents "
              "WHERE student_id=? ORDER BY incident_date DESC, id DESC");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["date"] = q.value(1).toString();
        m["category"] = q.value(2).toString();
        m["description"] = q.value(3).toString();
        m["sanction"] = q.value(4).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addIncident(const QVariantMap &v)
{
    if (!can("discipline.record")) return false;
    const int studentId = v.value("studentId").toInt();
    const QDate date = QDate::fromString(v.value("date").toString(), "yyyy-MM-dd");
    const QString category = v.value("category").toString().trimmed();
    if (studentId <= 0 || !date.isValid() || category.isEmpty()) {
        emit errorOccurred(QStringLiteral("Élève, date (AAAA-MM-JJ) et catégorie requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO incidents(student_id,incident_date,category,description,sanction,recorded_by) VALUES(?,?,?,?,?,?)");
    q.addBindValue(studentId);
    q.addBindValue(date.toString("yyyy-MM-dd"));
    q.addBindValue(category);
    q.addBindValue(v.value("description").toString().trimmed());
    q.addBindValue(v.value("sanction").toString().trimmed());
    q.addBindValue(m_userId);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "incident", q.lastInsertId().toInt(), category);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::deliberation(const QString &className, const QString &term) const
{
    QVariantList out;
    if (!can("deliberations.view")) return out;
    QSqlQuery st(m_db.db());
    st.prepare("SELECT id,last_name || ' ' || first_name FROM students WHERE current_class=? AND deleted_at IS NULL "
               "AND graduated_at IS NULL ORDER BY last_name,first_name");
    st.addBindValue(className);
    if (!st.exec()) return out;
    while (st.next()) {
        const int sid = st.value(0).toInt();
        QSqlQuery g(m_db.db());
        g.prepare("SELECT ROUND(AVG((gr.score*20.0)/e.max_score),2), COALESCE(sb.coefficient,1) FROM grades gr "
                  "JOIN exams e ON e.id=gr.exam_id JOIN courses c ON c.id=e.course_id "
                  "LEFT JOIN subjects sb ON sb.name=c.subject WHERE gr.student_id=? AND e.term=? "
                  "GROUP BY c.subject, COALESCE(sb.coefficient,1)");
        g.addBindValue(sid);
        g.addBindValue(term);
        double sum = 0, coefSum = 0;
        bool any = false;
        if (g.exec()) {
            while (g.next()) {
                any = true;
                sum += g.value(0).toDouble() * g.value(1).toDouble();
                coefSum += g.value(1).toDouble();
            }
        }
        QVariantMap m;
        m["studentId"] = sid;
        m["name"] = st.value(1).toString();
        if (any && coefSum > 0) {
            const double avg = sum / coefSum;
            m["average"] = QString::number(avg, 'f', 2);
            m["decision"] = avg >= 10 ? QStringLiteral("Admis") : avg >= 8 ? QStringLiteral("Rattrapage") : QStringLiteral("Ajourné");
        } else {
            m["average"] = QString();
            m["decision"] = QStringLiteral("—");
        }
        out << m;
    }
    return out;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

pm = 'src/core/PrintManager.cpp'
edit(pm, '    const double sigY = y + 90;\n    p.setFont(QFont("Arial", 10, QFont::Bold));\n    pg.text(370, sigY, settingText("signatory_title", "Le Frère Directeur"));\n    p.setPen(QPen(QColor("#667085"), 0.8));\n    p.drawLine(QPoint(pg.px(360), pg.px(sigY + 60)), QPoint(pg.px(550), pg.px(sigY + 60)));\n    return true;\n}\n\nbool PrintManager::printStudentCertificate',
     '''    y += 30;
    p.setFont(QFont("Arial", 10));
    QSqlQuery att(QSqlDatabase::database());
    att.prepare("SELECT COALESCE(SUM(status='absent'),0), COALESCE(SUM(status='late'),0) FROM attendance WHERE student_id=?");
    att.addBindValue(studentId);
    int absences = 0, lates = 0;
    if (att.exec() && att.next()) { absences = att.value(0).toInt(); lates = att.value(1).toInt(); }
    QSqlQuery inc(QSqlDatabase::database());
    inc.prepare("SELECT COUNT(*) FROM incidents WHERE student_id=?");
    inc.addBindValue(studentId);
    const int incidents = inc.exec() && inc.next() ? inc.value(0).toInt() : 0;
    pg.text(45, y, QStringLiteral("Absences : ") + QString::number(absences)
            + QStringLiteral("     Retards : ") + QString::number(lates)
            + QStringLiteral("     Incidents disciplinaires : ") + QString::number(incidents));

    const double sigY = y + 90;
    p.setFont(QFont("Arial", 10, QFont::Bold));
    pg.text(370, sigY, settingText("signatory_title", "Le Frère Directeur"));
    p.setPen(QPen(QColor("#667085"), 0.8));
    p.drawLine(QPoint(pg.px(360), pg.px(sigY + 60)), QPoint(pg.px(550), pg.px(sigY + 60)));
    return true;
}

bool PrintManager::printStudentCertificate''')

sb = 'qml/components/Sidebar.qml'
edit(sb, '                ["exams", "Examens & notes", "📝"],\n',
     '''                ["exams", "Examens & notes", "📝"],
                ["curriculum", "Matières & emploi du temps", "📐"],
                ["attendance", "Présences", "✅"],
                ["discipline", "Discipline", "⚠"],
                ["council", "Délibérations", "🎓"],
''')

mq = 'qml/Main.qml'
edit(mq, '"roles":16}', '"roles":16,"curriculum":17,"attendance":18,"discipline":19,"council":20}')
edit(mq, '                        RolesPage {}\n', '''                        RolesPage {}
                        CurriculumPage {}
                        AttendancePage {}
                        DisciplinePage {}
                        CouncilPage {}
''')

cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/RolesPage.qml\n', '''        qml/pages/RolesPage.qml
        qml/pages/CurriculumPage.qml
        qml/pages/AttendancePage.qml
        qml/pages/DisciplinePage.qml
        qml/pages/CouncilPage.qml
''')
print("phase 10 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: scolarité et pédagogie (matières, affectations, emploi du temps, présences, discipline, délibérations, livret)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-scolarite-pedagogie."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-scolarite-pedagogie"
