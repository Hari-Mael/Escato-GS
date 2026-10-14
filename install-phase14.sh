#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-affectation-bourses-etats main
git rm -q --ignore-unmatch install-phase*.sh || true

cat > qml/pages/FinanceExtraPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var studentOptions: []
    property var unallocatedRows: []
    property var openInvoiceRows: []
    property var scholarshipRows: []
    property var categoryRows: []
    property var statement: ({})

    function fmt(n) { return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar" }
    function refreshStudent() {
        var id = studentBox.currentValue
        if (!id) { unallocatedRows = []; openInvoiceRows = []; scholarshipRows = []; return }
        unallocatedRows = school.unallocatedPayments(id)
        openInvoiceRows = school.openInvoices(id)
        scholarshipRows = school.scholarshipsFor(id)
    }
    function refresh() {
        studentOptions = school.students().map(function(s) { return {id: s.id, label: s.lastName + " " + s.firstName + " (" + s.className + ")"} })
        categoryRows = school.expenseCategories()
        refreshStudent()
        statement = school.financialStatements(fromDate.text, toDate.text)
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

            Label { text: "Bourses, affectations et états financiers"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: studentColumn.implicitHeight + 40
                ColumnLayout {
                    id: studentColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Élève"; font.pixelSize: 18; font.bold: true }
                    ComboBox {
                        id: studentBox
                        Layout.fillWidth: true
                        model: root.studentOptions
                        textRole: "label"
                        valueRole: "id"
                        onCurrentValueChanged: root.refreshStudent()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: allocColumn.implicitHeight + 40
                ColumnLayout {
                    id: allocColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Affecter un paiement à une facture"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Un paiement peut couvrir plusieurs factures, ou une facture plusieurs paiements (paiements partiels). Le solde restant de chaque facture est mis à jour."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Repeater {
                        model: root.unallocatedRows
                        delegate: Label {
                            text: "Paiement " + modelData.paidAt + " · " + modelData.method + " · reste à affecter " + root.fmt(modelData.unallocated)
                            Layout.fillWidth: true
                        }
                    }
                    Repeater {
                        model: root.openInvoiceRows
                        delegate: Label {
                            text: "Facture " + modelData.month + " (échéance " + modelData.dueDate + ") · reste à payer " + root.fmt(modelData.remaining)
                            color: "#C62828"; Layout.fillWidth: true
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        ComboBox { id: allocPayment; Layout.preferredWidth: 280; model: root.unallocatedRows; textRole: "label"; valueRole: "id" }
                        ComboBox { id: allocInvoice; Layout.preferredWidth: 260; model: root.openInvoiceRows; textRole: "label"; valueRole: "id" }
                        AppTextField { id: allocAmount; placeholderText: "Montant"; Layout.preferredWidth: 120; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Affecter"; highlighted: true
                            onClicked: school.allocatePayment(allocPayment.currentValue, allocInvoice.currentValue, parseFloat(allocAmount.text.replace(",", ".")) || 0)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: schColumn.implicitHeight + 40
                ColumnLayout {
                    id: schColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Bourses"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Une bourse en pourcentage réduit les mensualités générées après sa création."; color: "#667085"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    Repeater {
                        model: root.scholarshipRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.label; Layout.fillWidth: true }
                            Label { text: modelData.schoolYear; color: "#667085" }
                            Label { text: modelData.percent + " %"; font.bold: true }
                            AppButton { text: "Supprimer"; onClicked: school.deleteScholarship(modelData.id) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: schLabel; placeholderText: "Libellé (ex. Bourse d'excellence)"; Layout.fillWidth: true }
                        AppTextField { id: schPercent; placeholderText: "%"; Layout.preferredWidth: 90; inputMethodHints: Qt.ImhDigitsOnly }
                        AppTextField { id: schYear; placeholderText: "Année (ex. 2026-2027)"; Layout.preferredWidth: 170 }
                        AppButton {
                            text: "Ajouter la bourse"; highlighted: true
                            onClicked: if (school.addScholarship({studentId: studentBox.currentValue, label: schLabel.text,
                                                                  percent: parseFloat(schPercent.text.replace(",", ".")) || 0, schoolYear: schYear.text})) { schLabel.text = ""; schPercent.text = "" }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: catColumn.implicitHeight + 40
                ColumnLayout {
                    id: catColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Catégories de dépenses"; font.pixelSize: 18; font.bold: true }
                    Flow {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            model: root.categoryRows
                            delegate: AppButton {
                                text: modelData.name + "  ✕"
                                onClicked: school.deleteExpenseCategory(modelData.id)
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: catName; placeholderText: "Nouvelle catégorie"; Layout.fillWidth: true }
                        AppButton { text: "Ajouter"; highlighted: true; onClicked: if (school.addExpenseCategory(catName.text)) catName.text = "" }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: stateColumn.implicitHeight + 40
                ColumnLayout {
                    id: stateColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "États financiers et analytiques"; font.pixelSize: 18; font.bold: true }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: fromDate; placeholderText: "Du AAAA-MM-JJ"; Layout.preferredWidth: 160 }
                        AppTextField { id: toDate; placeholderText: "Au AAAA-MM-JJ"; Layout.preferredWidth: 160 }
                        AppButton { text: "Afficher"; highlighted: true; onClicked: root.refresh() }
                    }
                    Label { text: "Produits (encaissements) : " + root.fmt(root.statement.revenue || 0); font.bold: true; color: "#0F9D8F" }
                    Repeater {
                        model: root.statement.byMethod || []
                        delegate: Label { text: "   " + modelData.method + " : " + root.fmt(modelData.amount); color: "#667085" }
                    }
                    Label { text: "Charges (dépenses) : " + root.fmt(root.statement.expenses || 0); font.bold: true; color: "#C62828" }
                    Repeater {
                        model: root.statement.byCategory || []
                        delegate: Label { text: "   " + modelData.category + " : " + root.fmt(modelData.amount) + " (" + modelData.percent + " %)"; color: "#667085" }
                    }
                    Label {
                        text: "Résultat : " + root.fmt(root.statement.result || 0)
                        font.pixelSize: 18; font.bold: true
                        color: (root.statement.result || 0) >= 0 ? "#0F9D8F" : "#C62828"
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
    ("payments.allocate", "Affecter un paiement à une facture", "Finances", ["administrateur", "comptable"]),
    ("scholarships.manage", "Gérer les bourses des élèves", "Finances", ["administrateur", "comptable"]),
]

db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS payment_allocations(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payment_id INTEGER NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
            invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
            amount REAL NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS scholarships(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            label TEXT NOT NULL,
            percent REAL NOT NULL CHECK(percent > 0 AND percent <= 100),
            school_year TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS expense_categories(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')
seed = ["    if (!exec(\"INSERT OR IGNORE INTO expense_categories(name) VALUES ('Fournitures'),('Salaires'),('Eau et électricité'),('Entretien'),('Transport'),('Autres')\")) return false;"]
for key, label, group, roles in PERMS:
    seed.append('    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES(\'%s\',\'%s\',\'%s\')")) return false;' % (key, label.replace("'", "''"), group))
    vals = ",".join("('%s','%s',%d)" % (r, key, 1 if r in roles else 0) for r in ROLES)
    seed.append('    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES %s")) return false;' % vals)
edit(db, 'bool Database::seed()\n{\n', 'bool Database::seed()\n{\n' + "\n".join(seed) + "\n\n")

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QVariantList expenses() const;\n', '''    Q_INVOKABLE QVariantList expenses() const;
    Q_INVOKABLE QVariantList expenseCategories() const;
    Q_INVOKABLE bool addExpenseCategory(const QString &name);
    Q_INVOKABLE bool deleteExpenseCategory(int id);
    Q_INVOKABLE QVariantList unallocatedPayments(int studentId) const;
    Q_INVOKABLE QVariantList openInvoices(int studentId) const;
    Q_INVOKABLE bool allocatePayment(int paymentId, int invoiceId, double amount);
    Q_INVOKABLE QVariantList scholarshipsFor(int studentId) const;
    Q_INVOKABLE bool addScholarship(const QVariantMap &v);
    Q_INVOKABLE bool deleteScholarship(int id);
    Q_INVOKABLE QVariantMap financialStatements(const QString &fromDate, const QString &toDate) const;
''')
edit(hd, '    bool periodOpenFor(const QString &dateText) const;\n', '    bool periodOpenFor(const QString &dateText) const;\n    double scholarshipPercent(int studentId) const;\n')

cpp = 'src/core/SchoolApp.cpp'
edit(cpp, 'i.addBindValue(f.value(0));i.exec();}}',
     'i.addBindValue(f.value(0).toDouble()*(1.0-scholarshipPercent(s.value(0).toInt())/100.0));i.exec();}}')

s = open(cpp, encoding='utf-8').read()
s += '''
double SchoolApp::scholarshipPercent(int studentId) const
{
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE(SUM(percent),0) FROM scholarships WHERE student_id=?");
    q.addBindValue(studentId);
    const double p = q.exec() && q.next() ? q.value(0).toDouble() : 0.0;
    return p > 100.0 ? 100.0 : p;
}

QVariantList SchoolApp::expenseCategories() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name FROM expense_categories ORDER BY name")) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); out << m; }
    return out;
}

bool SchoolApp::addExpenseCategory(const QString &name)
{
    if (!can("accounting.write")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty()) { emit errorOccurred(QStringLiteral("Nom de la catégorie requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO expense_categories(name) VALUES(?)");
    q.addBindValue(n);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette catégorie existe déjà.") : q.lastError().text()); return false; }
    audit("create", "expense_category", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteExpenseCategory(int id)
{
    if (!can("accounting.write")) return false;
    QSqlQuery used(m_db.db());
    used.prepare("SELECT COUNT(*) FROM expenses e JOIN expense_categories c ON c.name=e.category WHERE c.id=?");
    used.addBindValue(id);
    if (used.exec() && used.next() && used.value(0).toInt() > 0) {
        emit errorOccurred(QStringLiteral("Cette catégorie est utilisée par des dépenses : elle ne peut pas être supprimée."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM expense_categories WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "expense_category", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::unallocatedPayments(int studentId) const
{
    QVariantList out;
    if (!can("payments.allocate")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT p.id,p.amount,p.method,substr(p.paid_at,1,10),p.amount - COALESCE((SELECT SUM(a.amount) FROM payment_allocations a WHERE a.payment_id=p.id),0) "
              "FROM payments p WHERE p.student_id=? ORDER BY p.paid_at");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        const double left = q.value(4).toDouble();
        if (left <= 0.005) continue;
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["amount"] = q.value(1).toDouble();
        m["method"] = q.value(2).toString();
        m["paidAt"] = q.value(3).toString();
        m["unallocated"] = left;
        m["label"] = q.value(3).toString() + " · " + q.value(2).toString() + " · reste " + QString::number(left, 'f', 0) + " Ar";
        out << m;
    }
    return out;
}

QVariantList SchoolApp::openInvoices(int studentId) const
{
    QVariantList out;
    if (!can("payments.allocate")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT i.id,i.period_month,i.due_date,i.amount - COALESCE((SELECT SUM(a.amount) FROM payment_allocations a WHERE a.invoice_id=i.id),0) "
              "FROM invoices i WHERE i.student_id=? AND i.status IN ('pending','late') ORDER BY i.due_date");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        const double left = q.value(3).toDouble();
        if (left <= 0.005) continue;
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["month"] = q.value(1).toString();
        m["dueDate"] = q.value(2).toString();
        m["remaining"] = left;
        m["label"] = q.value(1).toString() + " · reste " + QString::number(left, 'f', 0) + " Ar";
        out << m;
    }
    return out;
}

bool SchoolApp::allocatePayment(int paymentId, int invoiceId, double amount)
{
    if (!can("payments.allocate")) return false;
    if (amount <= 0) { emit errorOccurred(QStringLiteral("Montant à affecter (> 0) requis.")); return false; }
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    QSqlQuery p(db);
    p.prepare("SELECT p.student_id, p.amount - COALESCE((SELECT SUM(a.amount) FROM payment_allocations a WHERE a.payment_id=p.id),0) FROM payments p WHERE p.id=?");
    p.addBindValue(paymentId);
    if (!p.exec() || !p.next()) { db.rollback(); emit errorOccurred(QStringLiteral("Paiement introuvable.")); return false; }
    const int studentId = p.value(0).toInt();
    const double paymentLeft = p.value(1).toDouble();
    QSqlQuery i(db);
    i.prepare("SELECT i.student_id, i.amount - COALESCE((SELECT SUM(a.amount) FROM payment_allocations a WHERE a.invoice_id=i.id),0) FROM invoices i WHERE i.id=? AND i.status IN ('pending','late')");
    i.addBindValue(invoiceId);
    if (!i.exec() || !i.next()) { db.rollback(); emit errorOccurred(QStringLiteral("Facture introuvable ou déjà soldée.")); return false; }
    if (i.value(0).toInt() != studentId) { db.rollback(); emit errorOccurred(QStringLiteral("La facture et le paiement n'appartiennent pas au même élève.")); return false; }
    const double invoiceLeft = i.value(1).toDouble();
    if (amount > paymentLeft + 0.005 || amount > invoiceLeft + 0.005) {
        db.rollback();
        emit errorOccurred(QStringLiteral("Montant supérieur au reste du paiement ou de la facture."));
        return false;
    }
    QSqlQuery ins(db);
    ins.prepare("INSERT INTO payment_allocations(payment_id,invoice_id,amount) VALUES(?,?,?)");
    ins.addBindValue(paymentId);
    ins.addBindValue(invoiceId);
    ins.addBindValue(amount);
    if (!ins.exec()) { db.rollback(); emit errorOccurred(ins.lastError().text()); return false; }
    if (amount >= invoiceLeft - 0.005) {
        QSqlQuery up(db);
        up.prepare("UPDATE invoices SET status='paid', payment_id=COALESCE(payment_id,?) WHERE id=?");
        up.addBindValue(paymentId);
        up.addBindValue(invoiceId);
        if (!up.exec()) { db.rollback(); return false; }
    }
    db.commit();
    audit("update", "allocation", invoiceId, "paiement " + QString::number(paymentId) + " : " + QString::number(amount, 'f', 0) + " Ar");
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::scholarshipsFor(int studentId) const
{
    QVariantList out;
    if (!can("scholarships.manage")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,label,percent,COALESCE(school_year,'') FROM scholarships WHERE student_id=? ORDER BY id");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["label"] = q.value(1).toString();
        m["percent"] = q.value(2).toDouble();
        m["schoolYear"] = q.value(3).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addScholarship(const QVariantMap &v)
{
    if (!can("scholarships.manage")) return false;
    const int studentId = v.value("studentId").toInt();
    const QString label = v.value("label").toString().trimmed();
    const double percent = v.value("percent").toDouble();
    if (studentId <= 0 || label.isEmpty() || percent <= 0 || percent > 100) {
        emit errorOccurred(QStringLiteral("Élève, libellé et pourcentage entre 0 et 100 requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO scholarships(student_id,label,percent,school_year) VALUES(?,?,?,?)");
    q.addBindValue(studentId);
    q.addBindValue(label);
    q.addBindValue(percent);
    q.addBindValue(v.value("schoolYear").toString().trimmed());
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "scholarship", q.lastInsertId().toInt(), label);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteScholarship(int id)
{
    if (!can("scholarships.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM scholarships WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "scholarship", id);
    emit dataChanged();
    return true;
}

QVariantMap SchoolApp::financialStatements(const QString &fromDate, const QString &toDate) const
{
    QVariantMap out;
    if (!can("finance.reports")) return out;
    const QString from = fromDate.trimmed().isEmpty() ? QStringLiteral("0000-01-01") : fromDate.trimmed();
    const QString to = toDate.trimmed().isEmpty() ? QStringLiteral("9999-12-31") : toDate.trimmed();

    QVariantList byMethod;
    double revenue = 0;
    QSqlQuery r(m_db.db());
    r.prepare("SELECT method, SUM(amount) FROM payments WHERE substr(paid_at,1,10) BETWEEN ? AND ? GROUP BY method ORDER BY method");
    r.addBindValue(from);
    r.addBindValue(to);
    if (r.exec()) {
        while (r.next()) {
            QVariantMap m;
            m["method"] = r.value(0).toString();
            m["amount"] = r.value(1).toDouble();
            revenue += r.value(1).toDouble();
            byMethod << m;
        }
    }

    QVariantList byCategory;
    double expenses = 0;
    QSqlQuery e(m_db.db());
    e.prepare("SELECT category, SUM(amount) FROM expenses WHERE expense_date BETWEEN ? AND ? GROUP BY category ORDER BY SUM(amount) DESC");
    e.addBindValue(from);
    e.addBindValue(to);
    if (e.exec()) {
        while (e.next()) {
            expenses += e.value(1).toDouble();
            QVariantMap m;
            m["category"] = e.value(0).toString();
            m["amount"] = e.value(1).toDouble();
            byCategory << m;
        }
    }
    for (int k = 0; k < byCategory.size(); ++k) {
        QVariantMap m = byCategory[k].toMap();
        m["percent"] = expenses > 0 ? QString::number(m["amount"].toDouble() * 100.0 / expenses, 'f', 1) : QStringLiteral("0.0");
        byCategory[k] = m;
    }

    out["byMethod"] = byMethod;
    out["byCategory"] = byCategory;
    out["revenue"] = revenue;
    out["expenses"] = expenses;
    out["result"] = revenue - expenses;
    return out;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sb = 'qml/components/Sidebar.qml'
edit(sb, '                ["treasury", "Caisse, banque et clôtures", "🏦"],\n',
     '                ["treasury", "Caisse, banque et clôtures", "🏦"],\n                ["finextra", "Bourses, affectations et états", "📑"],\n')
mq = 'qml/Main.qml'
edit(mq, '"treasury":23}', '"treasury":23,"finextra":24}')
edit(mq, '                        AccountingExtraPage {}\n', '                        AccountingExtraPage {}\n                        FinanceExtraPage {}\n')
cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/AccountingExtraPage.qml\n', '        qml/pages/AccountingExtraPage.qml\n        qml/pages/FinanceExtraPage.qml\n')
print("phase 14 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: affectation des paiements aux factures, bourses, catégories de dépenses gérées, états financiers et analytiques"

echo ""
echo "Commit créé sur la branche feat/escato-gs-affectation-bourses-etats."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-affectation-bourses-etats"
