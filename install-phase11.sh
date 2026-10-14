#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-administration-scolaire main
git rm -q --ignore-unmatch install-phase*.sh || true

cat > qml/pages/AdministrationPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property bool canStructure: false
    property bool canCalendar: false
    property var cycleRows: []
    property var levelRows: []
    property var classRows: []
    property var roomRows: []
    property var eventRows: []
    readonly property var eventKinds: ["evenement", "ferie", "vacances"]
    readonly property var eventLabels: ["Événement", "Jour férié", "Vacances"]

    function refreshPerms() {
        canStructure = school.can("structure.manage")
        canCalendar = school.can("calendar.manage")
    }
    function refresh() {
        refreshPerms()
        cycleRows = school.cycles()
        levelRows = school.levels()
        classRows = school.schoolClasses()
        roomRows = school.rooms()
        eventRows = school.calendarEvents()
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

            Label { text: "Administration scolaire"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: cycleColumn.implicitHeight + 40
                ColumnLayout {
                    id: cycleColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Cycles scolaires"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.cycleRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.fillWidth: true }
                            AppButton { text: "Supprimer"; visible: root.canStructure; onClicked: school.deleteCycle(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canStructure
                        AppTextField { id: cycleName; placeholderText: "Nouveau cycle"; Layout.fillWidth: true }
                        AppButton { text: "Ajouter"; highlighted: true; onClicked: if (school.addCycle(cycleName.text)) cycleName.text = "" }
                    }

                    Label { text: "Niveaux scolaires"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.levelRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; Layout.fillWidth: true }
                            Label { text: modelData.cycleName; color: "#667085" }
                            AppButton { text: "Supprimer"; visible: root.canStructure; onClicked: school.deleteLevel(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canStructure
                        AppTextField { id: levelName; placeholderText: "Nouveau niveau (ex. CP)"; Layout.fillWidth: true }
                        ComboBox { id: levelCycle; Layout.preferredWidth: 180; model: root.cycleRows; textRole: "name"; valueRole: "id" }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: if (school.addLevel(levelName.text, levelCycle.currentValue)) levelName.text = ""
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: classColumn.implicitHeight + 40
                ColumnLayout {
                    id: classColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Classes"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Une classe désactivée n'apparaît plus dans les listes, mais ses élèves et son historique sont conservés."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Repeater {
                        model: root.classRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; font.bold: true; Layout.preferredWidth: 140 }
                            Label { text: modelData.cycleName + " · " + modelData.levelName; color: "#667085"; Layout.fillWidth: true }
                            Label { text: modelData.isActive ? "Active" : "Désactivée"; color: modelData.isActive ? "#0F9D8F" : "#C62828" }
                            AppButton {
                                text: modelData.isActive ? "Désactiver" : "Réactiver"
                                visible: root.canStructure
                                onClicked: school.setSchoolClassActive(modelData.id, !modelData.isActive)
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canStructure
                        AppTextField { id: className; placeholderText: "Nom de la classe (ex. CE3)"; Layout.fillWidth: true }
                        ComboBox { id: classLevel; Layout.preferredWidth: 200; model: root.levelRows; textRole: "name"; valueRole: "id" }
                        AppButton {
                            text: "Ajouter la classe"; highlighted: true
                            onClicked: if (school.addSchoolClass(className.text, classLevel.currentValue)) className.text = ""
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: roomColumn.implicitHeight + 40
                ColumnLayout {
                    id: roomColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Salles"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.roomRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; font.bold: true; Layout.fillWidth: true }
                            Label { text: modelData.capacity > 0 ? modelData.capacity + " places" : ""; color: "#667085" }
                            AppButton { text: "Supprimer"; visible: root.canStructure; onClicked: school.deleteRoom(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canStructure
                        AppTextField { id: roomName; placeholderText: "Nom de la salle"; Layout.fillWidth: true }
                        AppTextField { id: roomCapacity; placeholderText: "Places"; Layout.preferredWidth: 110; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: if (school.addRoom(roomName.text, parseInt(roomCapacity.text) || 0)) { roomName.text = ""; roomCapacity.text = "" }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: calendarColumn.implicitHeight + 40
                ColumnLayout {
                    id: calendarColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Calendrier scolaire"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.eventRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.startDate + (modelData.endDate !== modelData.startDate ? " → " + modelData.endDate : ""); Layout.preferredWidth: 220 }
                            Label { text: modelData.title; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: root.eventLabels[root.eventKinds.indexOf(modelData.kind)]; color: "#667085" }
                            AppButton { text: "Supprimer"; visible: root.canCalendar; onClicked: school.deleteCalendarEvent(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8; visible: root.canCalendar
                        AppTextField { id: eventTitle; placeholderText: "Titre (ex. Rentrée, Fête nationale)"; Layout.fillWidth: true }
                        AppTextField { id: eventStart; placeholderText: "Début AAAA-MM-JJ"; Layout.preferredWidth: 150 }
                        AppTextField { id: eventEnd; placeholderText: "Fin AAAA-MM-JJ"; Layout.preferredWidth: 150 }
                        ComboBox { id: eventKind; Layout.preferredWidth: 130; model: root.eventLabels }
                        AppButton {
                            text: "Ajouter"; highlighted: true
                            onClicked: {
                                if (school.addCalendarEvent({title: eventTitle.text, startDate: eventStart.text, endDate: eventEnd.text,
                                                             kind: root.eventKinds[eventKind.currentIndex]})) {
                                    eventTitle.text = ""; eventStart.text = ""; eventEnd.text = ""
                                }
                            }
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

db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS cycles(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            sort_order INTEGER NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS levels(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            cycle_id INTEGER NOT NULL REFERENCES cycles(id),
            sort_order INTEGER NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS school_classes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            level_id INTEGER NOT NULL REFERENCES levels(id),
            sort_order INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1
        ))",

        R"(CREATE TABLE IF NOT EXISTS rooms(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            capacity INTEGER NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS calendar_events(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('evenement','ferie','vacances'))
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')

seed_sql = [
    "INSERT OR IGNORE INTO cycles(id,name,sort_order) VALUES (1,'Primaire',1),(2,'Collège',2),(3,'Lycée',3)",
    "INSERT OR IGNORE INTO levels(id,name,cycle_id,sort_order) VALUES (1,'CP',1,1),(2,'CE',1,2),(3,'CM',1,3),(4,'6ème',2,4),(5,'5ème',2,5),(6,'4ème',2,6),(7,'3ème',2,7),(8,'2nde',3,8),(9,'1ère',3,9),(10,'Terminale',3,10)",
    "INSERT OR IGNORE INTO school_classes(id,name,level_id,sort_order) VALUES (1,'CP1',1,1),(2,'CP2',1,2),(3,'CE1',2,3),(4,'CE2',2,4),(5,'CM1',3,5),(6,'CM2',3,6),(7,'6ème 1',4,7),(8,'6ème 2',4,8),(9,'6ème 3',4,9),(10,'5ème 1',5,10),(11,'5ème 2',5,11),(12,'5ème 3',5,12),(13,'4ème 1',6,13),(14,'4ème 2',6,14),(15,'4ème 3',6,15),(16,'3ème 1',7,16),(17,'3ème 2',7,17),(18,'3ème 3',7,18),(19,'2nde 1',8,19),(20,'2nde 2',8,20),(21,'2nde 3',8,21),(22,'2nde 4',8,22),(23,'1ère L1',9,23),(24,'1ère L2',9,24),(25,'1ère S1',9,25),(26,'1ère S2',9,26),(27,'TL1',10,27),(28,'TL2',10,28),(29,'TS',10,29)",
]
perms = [("structure.manage", "Gérer cycles, niveaux, classes et salles", "Administration scolaire", ["administrateur"]),
         ("calendar.manage", "Gérer le calendrier scolaire et les jours fériés", "Administration scolaire", ["administrateur"])]
ROLES = ["administrateur", "enseignant", "eleve", "parent", "comptable"]
extra = []
for stmt in seed_sql:
    extra.append('    if (!exec("%s")) return false;' % stmt)
for key, label, group, roles in perms:
    extra.append('    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES(\'%s\',\'%s\',\'%s\')")) return false;' % (key, label.replace("'", "''"), group))
    vals = ",".join("('%s','%s',%d)" % (r, key, 1 if r in roles else 0) for r in ROLES)
    extra.append('    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES %s")) return false;' % vals)
edit(db, 'bool Database::seed()\n{\n', 'bool Database::seed()\n{\n' + "\n".join(extra) + "\n\n")

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QStringList classes() const;\n', '''    Q_INVOKABLE QStringList classes() const;

    Q_INVOKABLE QVariantList cycles() const;
    Q_INVOKABLE bool addCycle(const QString &name);
    Q_INVOKABLE bool deleteCycle(int id);
    Q_INVOKABLE QVariantList levels() const;
    Q_INVOKABLE bool addLevel(const QString &name, int cycleId);
    Q_INVOKABLE bool deleteLevel(int id);
    Q_INVOKABLE QVariantList schoolClasses() const;
    Q_INVOKABLE bool addSchoolClass(const QString &name, int levelId);
    Q_INVOKABLE bool setSchoolClassActive(int id, bool active);
    Q_INVOKABLE QVariantList rooms() const;
    Q_INVOKABLE bool addRoom(const QString &name, int capacity);
    Q_INVOKABLE bool deleteRoom(int id);
    Q_INVOKABLE QVariantList calendarEvents() const;
    Q_INVOKABLE bool addCalendarEvent(const QVariantMap &v);
    Q_INVOKABLE bool deleteCalendarEvent(int id);
''')

cpp = 'src/core/SchoolApp.cpp'
s = open(cpp, encoding='utf-8').read()
start = s.index('QStringList SchoolApp::classes() const\n')
end = s.index('\n}\n', start) + 3
s = s[:start] + '''QStringList SchoolApp::classes() const
{
    QStringList out;
    QSqlQuery q(m_db.db());
    if (q.exec("SELECT name FROM school_classes WHERE is_active=1 ORDER BY sort_order,id")) {
        while (q.next()) out << q.value(0).toString();
    }
    return out;
}
''' + s[end:]
s += '''
QVariantList SchoolApp::cycles() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name FROM cycles ORDER BY sort_order,id")) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); out << m; }
    return out;
}

bool SchoolApp::addCycle(const QString &name)
{
    if (!can("structure.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty()) { emit errorOccurred(QStringLiteral("Nom du cycle requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO cycles(name,sort_order) VALUES(?,(SELECT COALESCE(MAX(sort_order),0)+1 FROM cycles))");
    q.addBindValue(n);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce cycle existe déjà.") : q.lastError().text()); return false; }
    audit("create", "cycle", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteCycle(int id)
{
    if (!can("structure.manage")) return false;
    QSqlQuery c(m_db.db());
    c.prepare("SELECT COUNT(*) FROM levels WHERE cycle_id=?");
    c.addBindValue(id);
    if (c.exec() && c.next() && c.value(0).toInt() > 0) {
        emit errorOccurred(QStringLiteral("Ce cycle contient des niveaux : supprime-les d'abord."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM cycles WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "cycle", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::levels() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT l.id,l.name,l.cycle_id,c.name FROM levels l JOIN cycles c ON c.id=l.cycle_id "
                "ORDER BY c.sort_order,l.sort_order,l.id")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["cycleId"] = q.value(2).toInt();
        m["cycleName"] = q.value(3).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addLevel(const QString &name, int cycleId)
{
    if (!can("structure.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty() || cycleId <= 0) { emit errorOccurred(QStringLiteral("Nom du niveau et cycle requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO levels(name,cycle_id,sort_order) VALUES(?,?,(SELECT COALESCE(MAX(sort_order),0)+1 FROM levels))");
    q.addBindValue(n);
    q.addBindValue(cycleId);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce niveau existe déjà.") : q.lastError().text()); return false; }
    audit("create", "level", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteLevel(int id)
{
    if (!can("structure.manage")) return false;
    QSqlQuery c(m_db.db());
    c.prepare("SELECT COUNT(*) FROM school_classes WHERE level_id=?");
    c.addBindValue(id);
    if (c.exec() && c.next() && c.value(0).toInt() > 0) {
        emit errorOccurred(QStringLiteral("Ce niveau contient des classes : supprime-les ou désactive-les d'abord."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM levels WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "level", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::schoolClasses() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT k.id,k.name,k.level_id,l.name,c.name,k.is_active FROM school_classes k "
                "JOIN levels l ON l.id=k.level_id JOIN cycles c ON c.id=l.cycle_id ORDER BY k.sort_order,k.id")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["levelId"] = q.value(2).toInt();
        m["levelName"] = q.value(3).toString();
        m["cycleName"] = q.value(4).toString();
        m["isActive"] = q.value(5).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addSchoolClass(const QString &name, int levelId)
{
    if (!can("structure.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty() || levelId <= 0) { emit errorOccurred(QStringLiteral("Nom de la classe et niveau requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO school_classes(name,level_id,sort_order) VALUES(?,?,(SELECT COALESCE(MAX(sort_order),0)+1 FROM school_classes))");
    q.addBindValue(n);
    q.addBindValue(levelId);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette classe existe déjà.") : q.lastError().text()); return false; }
    audit("create", "school_class", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

bool SchoolApp::setSchoolClassActive(int id, bool active)
{
    if (!can("structure.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE school_classes SET is_active=? WHERE id=?");
    q.addBindValue(active ? 1 : 0);
    q.addBindValue(id);
    if (!q.exec() || q.numRowsAffected() != 1) return false;
    audit("update", "school_class", id, active ? "réactivée" : "désactivée");
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::rooms() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name,capacity FROM rooms ORDER BY name")) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); m["capacity"] = q.value(2).toInt(); out << m; }
    return out;
}

bool SchoolApp::addRoom(const QString &name, int capacity)
{
    if (!can("structure.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty() || capacity < 0) { emit errorOccurred(QStringLiteral("Nom de la salle requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO rooms(name,capacity) VALUES(?,?)");
    q.addBindValue(n);
    q.addBindValue(capacity);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette salle existe déjà.") : q.lastError().text()); return false; }
    audit("create", "room", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteRoom(int id)
{
    if (!can("structure.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM rooms WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "room", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::calendarEvents() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,title,start_date,end_date,kind FROM calendar_events ORDER BY start_date,id")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["title"] = q.value(1).toString();
        m["startDate"] = q.value(2).toString();
        m["endDate"] = q.value(3).toString();
        m["kind"] = q.value(4).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addCalendarEvent(const QVariantMap &v)
{
    if (!can("calendar.manage")) return false;
    const QString title = v.value("title").toString().trimmed();
    const QDate start = QDate::fromString(v.value("startDate").toString(), "yyyy-MM-dd");
    const QDate end = QDate::fromString(v.value("endDate").toString(), "yyyy-MM-dd");
    const QString kind = v.value("kind").toString();
    if (title.isEmpty() || !start.isValid() || !end.isValid() || end < start
        || !QStringList({"evenement", "ferie", "vacances"}).contains(kind)) {
        emit errorOccurred(QStringLiteral("Titre, dates valides (AAAA-MM-JJ, fin après début) et type requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO calendar_events(title,start_date,end_date,kind) VALUES(?,?,?,?)");
    q.addBindValue(title);
    q.addBindValue(start.toString("yyyy-MM-dd"));
    q.addBindValue(end.toString("yyyy-MM-dd"));
    q.addBindValue(kind);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "calendar_event", q.lastInsertId().toInt(), title);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteCalendarEvent(int id)
{
    if (!can("calendar.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM calendar_events WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "calendar_event", id);
    emit dataChanged();
    return true;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sb = 'qml/components/Sidebar.qml'
edit(sb, '                ["council", "Délibérations", "🎓"],\n',
     '                ["council", "Délibérations", "🎓"],\n                ["administration", "Administration scolaire", "🏛"],\n')

mq = 'qml/Main.qml'
edit(mq, '"council":20}', '"council":20,"administration":21}')
edit(mq, '                        CouncilPage {}\n', '                        CouncilPage {}\n                        AdministrationPage {}\n')

cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/CouncilPage.qml\n', '        qml/pages/CouncilPage.qml\n        qml/pages/AdministrationPage.qml\n')
print("phase 11 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: administration scolaire (cycles, niveaux, classes gérées, salles, calendrier scolaire, jours fériés et vacances)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-administration-scolaire."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-administration-scolaire"
