#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-parametres-audit main

cat > qml/pages/SettingsPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var periods: []
    property bool isAdmin: school.currentRole === "administrateur"

    function refreshPeriods() {
        periods = school.academicPeriods()
    }
    Component.onCompleted: {
        schoolName.text = school.setting("school_name")
        schoolCity.text = school.setting("school_city")
        signatory.text = school.setting("signatory_title")
        refreshPeriods()
    }
    Connections { target: school; function onDataChanged() { root.refreshPeriods() } }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 18

            Label { text: "Paramètres"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: accountColumn.implicitHeight + 40

                ColumnLayout {
                    id: accountColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 8
                    Label { text: "Compte"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Nom : " + school.currentUser }
                    Label { text: "Rôle : " + school.currentRole }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: schoolColumn.implicitHeight + 40

                ColumnLayout {
                    id: schoolColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10
                    Label { text: "Établissement et documents officiels"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Ces informations apparaissent sur les reçus, attestations, certificats et demandes de paiement."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    AppTextField { id: schoolName; Layout.fillWidth: true; placeholderText: "Nom de l'établissement"; enabled: root.isAdmin }
                    AppTextField { id: schoolCity; Layout.fillWidth: true; placeholderText: "Ville (ex. Tolagnaro)"; enabled: root.isAdmin }
                    AppTextField { id: signatory; Layout.fillWidth: true; placeholderText: "Titre du signataire (ex. Le Frère Directeur)"; enabled: root.isAdmin }
                    AppButton {
                        text: "Enregistrer"
                        highlighted: true
                        visible: root.isAdmin
                        onClicked: {
                            school.setSetting("school_name", schoolName.text)
                            school.setSetting("school_city", schoolCity.text)
                            school.setSetting("signatory_title", signatory.text)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: periodColumn.implicitHeight + 40

                ColumnLayout {
                    id: periodColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10
                    Label { text: "Périodes académiques"; font.pixelSize: 18; font.bold: true }
                    Label { visible: root.periods.length === 0; text: "Aucune période enregistrée."; color: "#667085" }
                    Repeater {
                        model: root.periods
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: modelData.name + "  (" + modelData.startDate + " → " + modelData.endDate + ")"
                                font.bold: modelData.isActive
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            Label { text: modelData.isActive ? "Active" : ""; color: "#0F9D8F"; font.bold: true }
                            AppButton {
                                text: "Activer"
                                visible: root.isAdmin && !modelData.isActive
                                onClicked: school.setActiveAcademicPeriod(modelData.id)
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.isAdmin
                        spacing: 8
                        AppTextField { id: periodName; placeholderText: "Ex. 2026 – 2027"; Layout.fillWidth: true }
                        AppTextField { id: periodStart; placeholderText: "Début AAAA-MM-JJ"; Layout.preferredWidth: 170 }
                        AppTextField { id: periodEnd; placeholderText: "Fin AAAA-MM-JJ"; Layout.preferredWidth: 170 }
                        AppButton {
                            text: "Ajouter"
                            highlighted: true
                            onClicked: {
                                if (school.addAcademicPeriod({name: periodName.text, startDate: periodStart.text, endDate: periodEnd.text})) {
                                    periodName.text = ""; periodStart.text = ""; periodEnd.text = ""
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

cat > qml/pages/AuditPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    property var rows: []

    function refresh() {
        rows = school.auditLogs(300)
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Journal d'audit"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            AppButton { text: "Actualiser"; onClicked: refresh() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: "white"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Date"; font.bold: true; color: "#667085"; Layout.preferredWidth: 170 }
                    Label { text: "Utilisateur"; font.bold: true; color: "#667085"; Layout.preferredWidth: 160 }
                    Label { text: "Action"; font.bold: true; color: "#667085"; Layout.preferredWidth: 110 }
                    Label { text: "Objet"; font.bold: true; color: "#667085"; Layout.preferredWidth: 170 }
                    Label { text: "Détails"; font.bold: true; color: "#667085"; Layout.fillWidth: true }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: rows
                    delegate: RowLayout {
                        width: ListView.view.width
                        Label { text: modelData.createdAt; Layout.preferredWidth: 170 }
                        Label { text: modelData.user; Layout.preferredWidth: 160; elide: Text.ElideRight }
                        Label { text: modelData.action; Layout.preferredWidth: 110 }
                        Label {
                            text: modelData.entity + (modelData.entityId ? " #" + modelData.entityId : "")
                            Layout.preferredWidth: 170; elide: Text.ElideRight
                        }
                        Label { text: modelData.details; color: "#667085"; Layout.fillWidth: true; elide: Text.ElideRight }
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
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS settings(
            key TEXT PRIMARY KEY,
            value TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS academic_periods(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')
edit(db, 'bool Database::seed()\n{\n', '''bool Database::seed()
{
    if (!exec("INSERT OR IGNORE INTO settings(key,value) VALUES('school_name','Ecole Sacré-Cœur'),"
              "('school_city','Tolagnaro'),('signatory_title','Le Frère Directeur')"))
        return false;

''')

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QVariantMap monthlyStats() const;\n', '''    Q_INVOKABLE QVariantMap monthlyStats() const;

    Q_INVOKABLE QString setting(const QString &key) const;
    Q_INVOKABLE bool setSetting(const QString &key, const QString &value);
    Q_INVOKABLE QVariantList academicPeriods() const;
    Q_INVOKABLE bool addAcademicPeriod(const QVariantMap &v);
    Q_INVOKABLE bool setActiveAcademicPeriod(int id);
    Q_INVOKABLE QVariantList auditLogs(int limit) const;
''')

cpp = 'src/core/SchoolApp.cpp'
s = open(cpp, encoding='utf-8').read()
s += '''\nQString SchoolApp::setting(const QString &key) const\n{\n    QSqlQuery q(m_db.db());\n    q.prepare("SELECT value FROM settings WHERE key=?");\n    q.addBindValue(key);\n    return q.exec() && q.next() ? q.value(0).toString() : QString();\n}\n\nbool SchoolApp::setSetting(const QString &key, const QString &value)\n{\n    if (!allowed({"administrateur"})) return false;\n    const QString k = key.trimmed();\n    if (k.isEmpty()) return false;\n    QSqlQuery q(m_db.db());\n    q.prepare("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value");\n    q.addBindValue(k);\n    q.addBindValue(value.trimmed());\n    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }\n    audit("update", "setting", 0, k);\n    emit dataChanged();\n    return true;\n}\n\nQVariantList SchoolApp::academicPeriods() const\n{\n    QVariantList out;\n    QSqlQuery q(m_db.db());\n    if (!q.exec("SELECT id,name,start_date,end_date,is_active FROM academic_periods ORDER BY start_date DESC")) return out;\n    while (q.next()) {\n        QVariantMap m;\n        m["id"] = q.value(0).toInt();\n        m["name"] = q.value(1).toString();\n        m["startDate"] = q.value(2).toString();\n        m["endDate"] = q.value(3).toString();\n        m["isActive"] = q.value(4).toInt() == 1;\n        out << m;\n    }\n    return out;\n}\n\nbool SchoolApp::addAcademicPeriod(const QVariantMap &v)\n{\n    if (!allowed({"administrateur"})) return false;\n    const QString name = v.value("name").toString().trimmed();\n    const QDate start = QDate::fromString(v.value("startDate").toString().trimmed(), "yyyy-MM-dd");\n    const QDate end = QDate::fromString(v.value("endDate").toString().trimmed(), "yyyy-MM-dd");\n    if (name.isEmpty() || !start.isValid() || !end.isValid() || end < start) {\n        emit errorOccurred(QStringLiteral("Nom, date de début et date de fin valides requis (AAAA-MM-JJ)."));\n        return false;\n    }\n    QSqlQuery q(m_db.db());\n    q.prepare("INSERT INTO academic_periods(name,start_date,end_date,is_active) VALUES(?,?,?,0)");\n    q.addBindValue(name);\n    q.addBindValue(start.toString("yyyy-MM-dd"));\n    q.addBindValue(end.toString("yyyy-MM-dd"));\n    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }\n    audit("create", "academic_period", q.lastInsertId().toInt(), name);\n    emit dataChanged();\n    return true;\n}\n\nbool SchoolApp::setActiveAcademicPeriod(int id)\n{\n    if (!allowed({"administrateur"})) return false;\n    QSqlDatabase db = m_db.db();\n    if (!db.transaction()) return false;\n    QSqlQuery off(db);\n    off.exec("UPDATE academic_periods SET is_active=0");\n    QSqlQuery on(db);\n    on.prepare("UPDATE academic_periods SET is_active=1 WHERE id=?");\n    on.addBindValue(id);\n    if (!on.exec() || on.numRowsAffected() != 1) { db.rollback(); return false; }\n    db.commit();\n    audit("update", "academic_period", id);\n    emit dataChanged();\n    return true;\n}\n\nQVariantList SchoolApp::auditLogs(int limit) const\n{\n    QVariantList out;\n    if (!allowed({"administrateur"})) return out;\n    QSqlQuery q(m_db.db());\n    q.prepare("SELECT a.created_at,COALESCE(u.name,'Système'),a.action,a.entity,a.entity_id,a.details "\n              "FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id ORDER BY a.id DESC LIMIT ?");\n    q.addBindValue(limit > 0 ? limit : 200);\n    if (!q.exec()) return out;\n    while (q.next()) {\n        QVariantMap m;\n        m["createdAt"] = q.value(0).toString();\n        m["user"] = q.value(1).toString();\n        m["action"] = q.value(2).toString();\n        m["entity"] = q.value(3).toString();\n        m["entityId"] = q.value(4).toInt();\n        m["details"] = q.value(5).toString();\n        out << m;\n    }\n    return out;\n}\n'''
open(cpp, 'w', encoding='utf-8').write(s)

pm = 'src/core/PrintManager.cpp'
edit(pm, '// En-tête officiel utilisé par les documents administratifs', '''QString settingText(const QString &key, const QString &fallback)\n{\n    QSqlQuery q(QSqlDatabase::database());\n    q.prepare("SELECT value FROM settings WHERE key=?");\n    q.addBindValue(key);\n    if (q.exec() && q.next() && !q.value(0).toString().trimmed().isEmpty())\n        return q.value(0).toString();\n    return fallback;\n}\n\n// En-tête officiel utilisé par les documents administratifs''')
edit(pm, 'pg.text(left + 95, top + 12, "Ecole Sacré-Cœur");',
     'pg.text(left + 95, top + 12, settingText("school_name", "Ecole Sacré-Cœur"));')
edit(pm, 'pg.text(90, 58, QStringLiteral("ESCATO GS"));',
     'pg.text(90, 58, settingText("school_name", "Ecole Sacré-Cœur"));')
edit(pm, 'pg.text(270, sigY, QStringLiteral("Le comptable"));',
     'pg.text(270, sigY, settingText("signatory_title", "Le Frère Directeur"));')
edit(pm, 'pg.text(370, sigY, QStringLiteral("Le comptable"));',
     'pg.text(370, sigY, settingText("signatory_title", "Le Frère Directeur"));')
edit(pm, 'pg.text(x + 16, y + 24, QStringLiteral("ESCATO GS"));',
     'pg.text(x + 16, y + 24, settingText("school_name", "Ecole Sacré-Cœur"));')
edit(pm, 'pg.text(45, y, QStringLiteral("Le Frère Directeur de l\'établissement certifie que :"));',
     'pg.text(45, y, settingText("signatory_title", "Le Frère Directeur") + QStringLiteral(" de l\'établissement certifie que :"));')
edit(pm, 'pg.text(340, y, QStringLiteral("Le Frère Directeur"));',
     'pg.text(340, y, settingText("signatory_title", "Le Frère Directeur"));')
edit(pm, 'pg.text(45, y, QStringLiteral("Fait à Tolagnaro, le ") + today.toString(QStringLiteral("dd/MM/yyyy")));',
     'pg.text(45, y, QStringLiteral("Fait à ") + settingText("school_city", "Tolagnaro") + QStringLiteral(", le ") + today.toString(QStringLiteral("dd/MM/yyyy")));')

sb = 'qml/components/Sidebar.qml'
edit(sb, '["bulletin", "Bulletins", "📄"]', '["bulletin", "Bulletins", "📄"],\n                ["audit", "Journal d\'audit", "📜"]')

mq = 'qml/Main.qml'
edit(mq, '"bulletin":12,"settings":13}', '"bulletin":12,"settings":13,"audit":14}')
edit(mq, 'SettingsPage {}\n', 'SettingsPage {}\n                        AuditPage {}\n')

cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/FamilyPortal.qml\n', '        qml/pages/FamilyPortal.qml\n        qml/pages/AuditPage.qml\n')
print("phase 4 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: paramètres de l'établissement, périodes académiques, journal d'audit; en-tête École Sacré-Cœur sur reçus et cartes; signataire Frère Directeur"

echo ""
echo "Commit créé sur la branche feat/escato-gs-parametres-audit."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-parametres-audit"
