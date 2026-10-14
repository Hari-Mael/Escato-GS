#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-finance-documents main
git rm -q --ignore-unmatch install-phase*.sh || true

cat > qml/pages/FinanceReportsPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property bool canReports: false
    property int reportIndex: 0
    property var overdueRows: []
    property var classRows: []
    property var parentRows: []
    property var monthRows: []
    property var historyRows: []
    readonly property var reportNames: ["Impayés", "Situation par classe", "Situation par parent", "Tableau financier mensuel", "Historique des documents"]

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function refreshPerms() {
        canReports = school.can("finance.reports")
    }
    function refresh() {
        refreshPerms()
        if (!canReports) return
        overdueRows = school.overdueByStudent(asOfDate.text)
        var all = school.balanceOverview("", "").students || []
        var byClass = {}
        for (var i = 0; i < all.length; ++i) {
            var s = all[i]
            if (!byClass[s.className]) byClass[s.className] = {className: s.className, billed: 0, collected: 0, balance: 0, count: 0}
            byClass[s.className].billed += s.billed
            byClass[s.className].collected += s.collected
            byClass[s.className].balance += s.balance
            byClass[s.className].count += 1
        }
        classRows = Object.keys(byClass).sort().map(function(k) { return byClass[k] })
        parentRows = school.parentBalances()
        monthRows = school.monthlyCollections(parseInt(yearField.text) || new Date().getFullYear())
        historyRows = school.documentHistory(300)
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Label { text: "Rapports financiers"; font.pixelSize: 28; font.bold: true; Layout.fillWidth: true }
            ComboBox {
                id: reportBox
                Layout.preferredWidth: 280
                model: root.reportNames
                onCurrentIndexChanged: root.reportIndex = currentIndex
            }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: 8
            visible: root.reportIndex === 0
            Label { text: "Impayés au" }
            AppTextField { id: asOfDate; Layout.preferredWidth: 160; placeholderText: "AAAA-MM-JJ (vide = aujourd'hui)" }
            AppButton { text: "Actualiser"; highlighted: true; onClicked: root.refresh() }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            visible: root.reportIndex === 3
            Label { text: "Année" }
            AppTextField { id: yearField; text: String(new Date().getFullYear()); Layout.preferredWidth: 100; inputMethodHints: Qt.ImhDigitsOnly; onTextChanged: root.refresh() }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: "white"; border.color: "#E3E8EE"
            visible: root.canReports
            ListView {
                anchors.fill: parent; anchors.margins: 14; clip: true
                model: root.reportIndex === 0 ? root.overdueRows
                     : root.reportIndex === 1 ? root.classRows
                     : root.reportIndex === 2 ? root.parentRows
                     : root.reportIndex === 3 ? root.monthRows
                     : root.historyRows
                delegate: RowLayout {
                    width: ListView.view.width
                    height: 40
                    Label {
                        text: root.reportIndex === 0 ? modelData.name
                            : root.reportIndex === 1 ? modelData.className
                            : root.reportIndex === 2 ? modelData.name
                            : root.reportIndex === 3 ? modelData.label
                            : modelData.createdAt + " · " + modelData.docType + " #" + modelData.refId
                        Layout.fillWidth: true; elide: Text.ElideRight
                    }
                    Label {
                        visible: root.reportIndex === 0
                        text: modelData.className
                        color: "#667085"; Layout.preferredWidth: 120
                    }
                    Label {
                        visible: root.reportIndex === 0 || root.reportIndex === 1 || root.reportIndex === 2 || root.reportIndex === 3
                        text: root.reportIndex === 0 ? root.fmt(modelData.total) + (modelData.oldestDue ? "  (depuis " + modelData.oldestDue + ")" : "")
                            : root.reportIndex === 1 ? root.fmt(modelData.balance)
                            : root.reportIndex === 2 ? root.fmt(modelData.balance)
                            : "encaissé " + root.fmt(modelData.collected) + " / facturé " + root.fmt(modelData.billed)
                        font.bold: true; Layout.preferredWidth: 300
                        color: root.reportIndex === 3 ? "#0B2A43" : (modelData.balance > 0 || modelData.total > 0 ? "#C62828" : "#0F9D8F")
                    }
                    AppButton {
                        visible: root.reportIndex === 0
                        text: "Relancer"
                        onClicked: school.processPaymentReminders()
                    }
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

db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS document_history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            doc_type TEXT NOT NULL,
            ref_id INTEGER NOT NULL DEFAULT 0,
            label TEXT,
            user_id INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')
perms = [("finance.reports", "Voir les rapports financiers (impayés, situations, tableau financier)", "Finances", ["administrateur", "comptable"]),
         ("documents.history", "Consulter l'historique des documents imprimés", "Documents officiels", ["administrateur", "comptable"])]
ROLES = ["administrateur", "enseignant", "eleve", "parent", "comptable"]
extra = []
for key, label, group, roles in perms:
    extra.append('    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES(\'%s\',\'%s\',\'%s\')")) return false;' % (key, label.replace("'", "''"), group))
    vals = ",".join("('%s','%s',%d)" % (r, key, 1 if r in roles else 0) for r in ROLES)
    extra.append('    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES %s")) return false;' % vals)
edit(db, 'bool Database::seed()\n{\n', 'bool Database::seed()\n{\n' + "\n".join(extra) + "\n\n")

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE bool processPaymentReminders();\n', '''    Q_INVOKABLE bool processPaymentReminders();
    Q_INVOKABLE QVariantList overdueByStudent(const QString &asOf) const;
    Q_INVOKABLE QVariantList parentBalances() const;
    Q_INVOKABLE QVariantList monthlyCollections(int year) const;
    Q_INVOKABLE QVariantList documentHistory(int limit) const;
    void logDocument(const QString &type, int refId, const QString &label);
''')

cpp = 'src/core/SchoolApp.cpp'
s = open(cpp, encoding='utf-8').read()
s += '''
void SchoolApp::logDocument(const QString &type, int refId, const QString &label)
{
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO document_history(doc_type,ref_id,label,user_id) VALUES(?,?,?,?)");
    q.addBindValue(type);
    q.addBindValue(refId);
    q.addBindValue(label);
    q.addBindValue(m_userId > 0 ? QVariant(m_userId) : QVariant());
    q.exec();
}

QVariantList SchoolApp::documentHistory(int limit) const
{
    QVariantList out;
    if (!can("documents.history")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT h.created_at,COALESCE(u.name,'Système'),h.doc_type,h.ref_id,COALESCE(h.label,'') "
              "FROM document_history h LEFT JOIN users u ON u.id=h.user_id ORDER BY h.id DESC LIMIT ?");
    q.addBindValue(limit > 0 ? limit : 200);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["createdAt"] = q.value(0).toString();
        m["user"] = q.value(1).toString();
        m["docType"] = q.value(2).toString();
        m["refId"] = q.value(3).toInt();
        m["label"] = q.value(4).toString();
        out << m;
    }
    return out;
}

QVariantList SchoolApp::overdueByStudent(const QString &asOf) const
{
    QVariantList out;
    if (!can("finance.reports")) return out;
    const QString d = asOf.trimmed().isEmpty() ? QDate::currentDate().toString("yyyy-MM-dd") : asOf.trimmed();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT s.id, s.last_name || ' ' || s.first_name, s.current_class, "
              "COALESCE((SELECT SUM(i.amount) FROM invoices i WHERE i.student_id=s.id AND i.status IN ('pending','late') AND i.due_date < ?),0), "
              "COALESCE((SELECT SUM(o.amount) FROM one_time_fees o WHERE o.student_id=s.id AND o.status='pending' AND o.due_date < ?),0), "
              "COALESCE((SELECT MIN(i.due_date) FROM invoices i WHERE i.student_id=s.id AND i.status IN ('pending','late') AND i.due_date < ?),'') "
              "FROM students s WHERE s.deleted_at IS NULL AND s.graduated_at IS NULL");
    q.addBindValue(d); q.addBindValue(d); q.addBindValue(d);
    if (!q.exec()) return out;
    while (q.next()) {
        const double monthly = q.value(3).toDouble();
        const double oneTime = q.value(4).toDouble();
        if (monthly + oneTime <= 0) continue;
        QVariantMap m;
        m["studentId"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["className"] = q.value(2).toString();
        m["monthlyDue"] = monthly;
        m["oneTimeDue"] = oneTime;
        m["total"] = monthly + oneTime;
        m["oldestDue"] = q.value(5).toString();
        out << m;
    }
    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap()["total"].toDouble() > b.toMap()["total"].toDouble();
    });
    return out;
}

QVariantList SchoolApp::parentBalances() const
{
    QVariantList out;
    if (!can("finance.reports")) return out;
    QSqlQuery parents(m_db.db());
    if (!parents.exec("SELECT id,name,email FROM users WHERE role='parent' AND deleted_at IS NULL ORDER BY name")) return out;
    while (parents.next()) {
        const int pid = parents.value(0).toInt();
        double billed = 0, collected = 0;
        QSqlQuery links(m_db.db());
        links.prepare("SELECT student_id FROM parent_student_links WHERE parent_user_id=?");
        links.addBindValue(pid);
        if (links.exec()) {
            while (links.next()) {
                const int sid = links.value(0).toInt();
                QSqlQuery b(m_db.db());
                b.prepare("SELECT COALESCE((SELECT SUM(amount) FROM invoices WHERE student_id=?),0) + "
                          "COALESCE((SELECT SUM(amount) FROM one_time_fees WHERE student_id=?),0), "
                          "COALESCE((SELECT SUM(amount) FROM payments WHERE student_id=?),0)");
                b.addBindValue(sid); b.addBindValue(sid); b.addBindValue(sid);
                if (b.exec() && b.next()) {
                    billed += b.value(0).toDouble();
                    collected += b.value(1).toDouble();
                }
            }
        }
        QVariantMap m;
        m["parentId"] = pid;
        m["name"] = parents.value(1).toString();
        m["email"] = parents.value(2).toString();
        m["billed"] = billed;
        m["collected"] = collected;
        m["balance"] = billed - collected;
        out << m;
    }
    return out;
}

QVariantList SchoolApp::monthlyCollections(int year) const
{
    QVariantList out;
    if (!can("finance.reports")) return out;
    for (int month = 1; month <= 12; ++month) {
        const QString ym = QStringLiteral("%1-%2").arg(year).arg(month, 2, 10, QLatin1Char('0'));
        QSqlQuery b(m_db.db());
        b.prepare("SELECT COALESCE((SELECT SUM(amount) FROM invoices WHERE strftime('%Y-%m',due_date)=?),0) + "
                  "COALESCE((SELECT SUM(amount) FROM one_time_fees WHERE strftime('%Y-%m',due_date)=?),0), "
                  "COALESCE((SELECT SUM(amount) FROM payments WHERE strftime('%Y-%m',paid_at)=?),0)");
        b.addBindValue(ym); b.addBindValue(ym); b.addBindValue(ym);
        QVariantMap m;
        m["month"] = ym;
        m["label"] = QDate(year, month, 1).toString("MMMM yyyy");
        m["billed"] = b.exec() && b.next() ? b.value(0).toDouble() : 0.0;
        m["collected"] = b.value(1).toDouble();
        out << m;
    }
    return out;
}
'''
if '#include <algorithm>' not in s:
    s = '#include <algorithm>\n' + s
open(cpp, 'w', encoding='utf-8').write(s)

ph = 'src/core/PrintManager.h'
s = open(ph, encoding='utf-8').read()
s = s.replace('class PrintManager : public QObject', 'class SchoolApp;\n\nclass PrintManager : public QObject', 1)
open(ph, 'w', encoding='utf-8').write(s)
edit(ph, '    Q_OBJECT\n', '    Q_OBJECT\n\npublic:\n    void setSchool(SchoolApp *school) { m_school = school; }\n\nprivate:\n    SchoolApp *m_school = nullptr;\n')

pmc = 'src/core/PrintManager.cpp'
edit(pmc, '#include "third_party/qrcodegen/qrcodegen.hpp"\n', '#include "third_party/qrcodegen/qrcodegen.hpp"\n#include "SchoolApp.h"\n')
types = {
    'printStudentCertificate': ('certificat', 'studentId'), 'exportStudentCertificatePdf': ('certificat', 'studentId'),
    'printStudentCard': ('carte', 'studentId'), 'exportStudentCardPdf': ('carte', 'studentId'),
    'printReceipt': ('recu', 'paymentId'), 'exportReceiptPdf': ('recu', 'paymentId'),
    'printPaymentRequest': ('demande_paiement', 'studentId'), 'exportPaymentRequestPdf': ('demande_paiement', 'studentId'),
    'printBulletin': ('bulletin', 'studentId'), 'exportBulletinPdf': ('bulletin', 'studentId'),
    'printAttestation': ('attestation', 'studentId'), 'exportAttestationPdf': ('attestation', 'studentId'),
}
s = open(pmc, encoding='utf-8').read()
for name, (doc, idp) in types.items():
    pat = re.compile(r'(bool PrintManager::' + name + r'\([^)]*\)\n\{\n)')
    m = pat.search(s)
    assert m, name
    if 'Attestation' in name:
        line = '    if (m_school) m_school->logDocument("attestation_" + kind, %s, QString());\n' % idp
    else:
        line = '    if (m_school) m_school->logDocument("%s", %s, QString());\n' % (doc, idp)
    s = s[:m.end()] + line + s[m.end():]
open(pmc, 'w', encoding='utf-8').write(s)

mc = 'src/main.cpp'
edit(mc, '    PrintManager printer;\n', '    PrintManager printer;\n    printer.setSchool(&school);\n')

sb = 'qml/components/Sidebar.qml'
edit(sb, '                ["administration", "Administration scolaire", "🏛"],\n',
     '                ["administration", "Administration scolaire", "🏛"],\n                ["finreports", "Rapports financiers", "📊"],\n')

mq = 'qml/Main.qml'
edit(mq, '"administration":21}', '"administration":21,"finreports":22}')
edit(mq, '                        AdministrationPage {}\n', '                        AdministrationPage {}\n                        FinanceReportsPage {}\n')

cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/AdministrationPage.qml\n', '        qml/pages/AdministrationPage.qml\n        qml/pages/FinanceReportsPage.qml\n')
print("phase 12 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: rapports financiers (impayés, situations par classe et par parent, tableau financier mensuel) et historique des documents imprimés"

echo ""
echo "Commit créé sur la branche feat/escato-gs-finance-documents."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-finance-documents"
