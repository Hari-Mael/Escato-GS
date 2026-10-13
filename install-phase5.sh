#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-frais-soldes main
git rm -q --ignore-unmatch install-phase4.sh install-phase5.sh || true

cat > qml/pages/FeesPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var tuitions: []
    property var overview: ({})
    property var studentRows: []
    property bool canEdit: school.currentRole === "administrateur" || school.currentRole === "comptable"

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
    Component.onCompleted: { refreshTuitions(); refreshOverview() }
    Connections {
        target: school
        function onDataChanged() { root.refreshTuitions(); root.refreshOverview() }
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
                                enabled: root.canEdit
                                inputMethodHints: Qt.ImhDigitsOnly
                            }
                            AppButton {
                                text: "Enregistrer"
                                visible: root.canEdit
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
QML

python3 <<'PY'
def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS class_tuitions(
            class_name TEXT PRIMARY KEY,
            monthly_amount REAL NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QVariantList auditLogs(int limit) const;\n', '''    Q_INVOKABLE QVariantList auditLogs(int limit) const;

    Q_INVOKABLE QVariantList classTuitions() const;
    Q_INVOKABLE bool setClassTuition(const QString &className, double monthlyAmount);
    Q_INVOKABLE QVariantMap balanceOverview(const QString &fromDate, const QString &toDate) const;
''')

cpp = 'src/core/SchoolApp.cpp'
edit(cpp, 'f.prepare("SELECT monthly_amount FROM student_fees WHERE student_id=? ORDER BY id DESC LIMIT 1");f.addBindValue(s.value(0));if(f.exec()&&f.next()){',
     'f.prepare("SELECT COALESCE((SELECT monthly_amount FROM student_fees WHERE student_id=? ORDER BY id DESC LIMIT 1),(SELECT ct.monthly_amount FROM class_tuitions ct JOIN students st ON st.current_class=ct.class_name WHERE st.id=? AND ct.monthly_amount>0))");f.addBindValue(s.value(0));f.addBindValue(s.value(0));if(f.exec()&&f.next()&&!f.value(0).isNull()){')

s = open(cpp, encoding='utf-8').read()
s += '''
QVariantList SchoolApp::classTuitions() const
{
    QVariantList out;
    for (const QString &c : classes()) {
        QSqlQuery q(m_db.db());
        q.prepare("SELECT monthly_amount FROM class_tuitions WHERE class_name=?");
        q.addBindValue(c);
        QVariantMap m;
        m["className"] = c;
        m["monthlyAmount"] = q.exec() && q.next() ? q.value(0).toDouble() : 0.0;
        out << m;
    }
    return out;
}

bool SchoolApp::setClassTuition(const QString &className, double monthlyAmount)
{
    if (!allowed({"administrateur", "comptable"})) return false;
    if (!classes().contains(className) || monthlyAmount < 0) {
        emit errorOccurred(QStringLiteral("Classe inconnue ou montant négatif."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO class_tuitions(class_name,monthly_amount) VALUES(?,?) "
              "ON CONFLICT(class_name) DO UPDATE SET monthly_amount=excluded.monthly_amount");
    q.addBindValue(className);
    q.addBindValue(monthlyAmount);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("update", "class_tuition", 0, className);
    emit dataChanged();
    return true;
}

QVariantMap SchoolApp::balanceOverview(const QString &fromDate, const QString &toDate) const
{
    QVariantMap out;
    if (!allowed({"administrateur", "comptable"})) return out;
    const QString from = fromDate.trimmed().isEmpty() ? QStringLiteral("0000-01-01") : fromDate.trimmed();
    const QString to = toDate.trimmed().isEmpty() ? QStringLiteral("9999-12-31") : toDate.trimmed();

    QSqlQuery b(m_db.db());
    b.prepare("SELECT COALESCE(SUM(amount),0), COALESCE(SUM(CASE WHEN status='late' THEN 1 ELSE 0 END),0) "
              "FROM invoices WHERE due_date BETWEEN ? AND ?");
    b.addBindValue(from); b.addBindValue(to);
    double billed = 0;
    if (b.exec() && b.next()) {
        billed = b.value(0).toDouble();
        out["lateCount"] = b.value(1).toInt();
    }

    QSqlQuery p(m_db.db());
    p.prepare("SELECT COALESCE(SUM(amount),0) FROM payments WHERE substr(paid_at,1,10) BETWEEN ? AND ?");
    p.addBindValue(from); p.addBindValue(to);
    double collected = 0;
    if (p.exec() && p.next()) collected = p.value(0).toDouble();

    out["billed"] = billed;
    out["collected"] = collected;
    out["balance"] = billed - collected;

    QVariantList rows;
    QSqlQuery s(m_db.db());
    s.prepare("SELECT s.id, s.last_name || ' ' || s.first_name, s.current_class, "
              "COALESCE((SELECT SUM(i.amount) FROM invoices i WHERE i.student_id=s.id AND i.due_date BETWEEN ? AND ?),0), "
              "COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.student_id=s.id AND substr(p.paid_at,1,10) BETWEEN ? AND ?),0) "
              "FROM students s WHERE s.deleted_at IS NULL AND s.graduated_at IS NULL ORDER BY s.current_class, s.last_name");
    for (int i = 0; i < 2; ++i) { s.addBindValue(from); s.addBindValue(to); }
    if (s.exec()) {
        while (s.next()) {
            QVariantMap m;
            const double sBilled = s.value(3).toDouble();
            const double sCollected = s.value(4).toDouble();
            m["studentId"] = s.value(0).toInt();
            m["name"] = s.value(1).toString();
            m["className"] = s.value(2).toString();
            m["billed"] = sBilled;
            m["collected"] = sCollected;
            m["balance"] = sBilled - sCollected;
            rows << m;
        }
    }
    out["students"] = rows;
    return out;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sb = 'qml/components/Sidebar.qml'
edit(sb, '["audit", "Journal d\'audit", "📜"]', '["audit", "Journal d\'audit", "📜"],\n                ["fees", "Frais et soldes", "🏷"]')

mq = 'qml/Main.qml'
edit(mq, '"settings":13,"audit":14}', '"settings":13,"audit":14,"fees":15}')
edit(mq, 'AuditPage {}\n', 'AuditPage {}\n                        FeesPage {}\n')

cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/AuditPage.qml\n', '        qml/pages/AuditPage.qml\n        qml/pages/FeesPage.qml\n')
print("phase 5 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: grille tarifaire par classe, vue d'ensemble des soldes et page Frais et soldes"

echo ""
echo "Commit créé sur la branche feat/escato-gs-frais-soldes."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-frais-soldes"
