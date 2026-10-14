#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-comptabilite-tresorerie main
git rm -q --ignore-unmatch install-phase*.sh || true

cat > qml/pages/AccountingExtraPage.qml <<'QML'
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
QML

python3 <<'PY'
def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

ROLES = ["administrateur", "enseignant", "eleve", "parent", "comptable"]
PERMS = [
    ("cash.manage", "Gérer la caisse (mouvements et clôture)", "Comptabilité", ["administrateur", "comptable"]),
    ("bank.manage", "Gérer les comptes bancaires et le rapprochement", "Comptabilité", ["administrateur", "comptable"]),
    ("closing.manage", "Clôturer et rouvrir les périodes comptables", "Comptabilité", ["administrateur"]),
    ("paymentmethods.manage", "Gérer les moyens de paiement", "Comptabilité", ["administrateur"]),
    ("schedule.manage", "Gérer les échéanciers de paiement", "Finances", ["administrateur", "comptable"]),
]

db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS cash_movements(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            movement_date TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('entree','sortie')),
            amount REAL NOT NULL,
            label TEXT NOT NULL,
            recorded_by INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS cash_closings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            closing_date TEXT NOT NULL UNIQUE,
            expected REAL NOT NULL,
            counted REAL NOT NULL,
            difference REAL NOT NULL,
            closed_by INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS bank_accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            bank TEXT,
            last4 TEXT,
            opening_balance REAL NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS bank_lines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id INTEGER NOT NULL REFERENCES bank_accounts(id) ON DELETE CASCADE,
            line_date TEXT NOT NULL,
            label TEXT NOT NULL,
            amount REAL NOT NULL,
            payment_id INTEGER UNIQUE REFERENCES payments(id) ON DELETE SET NULL
        ))",

        R"(CREATE TABLE IF NOT EXISTS payment_methods(
            code TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1
        ))",

        R"(CREATE TABLE IF NOT EXISTS payment_schedules(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            label TEXT NOT NULL,
            due_date TEXT NOT NULL,
            amount REAL NOT NULL
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')

extra = ["    if (!exec(\"INSERT OR IGNORE INTO payment_methods(code,label,is_active) VALUES ('mvola','Mvola',1),('orange_money','Orange Money',1),('airtel_money','Airtel Money',1),('virement','Virement bancaire',1),('especes','Espèces',1)\")) return false;"]
for key, label, group, roles in PERMS:
    extra.append('    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES(\'%s\',\'%s\',\'%s\')")) return false;' % (key, label.replace("'", "''"), group))
    vals = ",".join("('%s','%s',%d)" % (r, key, 1 if r in roles else 0) for r in ROLES)
    extra.append('    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES %s")) return false;' % vals)
edit(db, 'bool Database::seed()\n{\n', 'bool Database::seed()\n{\n' + "\n".join(extra) + "\n\n")

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QStringList paymentMethods() const;\n', '''    Q_INVOKABLE QStringList paymentMethods() const;
    Q_INVOKABLE QVariantList paymentMethodList() const;
    Q_INVOKABLE bool addPaymentMethod(const QString &code, const QString &label);
    Q_INVOKABLE bool setPaymentMethodActive(const QString &code, bool active);
    Q_INVOKABLE QVariantList accountingPeriods() const;
    Q_INVOKABLE bool addAccountingPeriod(const QVariantMap &v);
    Q_INVOKABLE bool setAccountingPeriodClosed(int id, bool closed);
    Q_INVOKABLE QVariantList cashMovements(const QString &date) const;
    Q_INVOKABLE bool addCashMovement(const QVariantMap &v);
    Q_INVOKABLE QVariantMap cashExpected(const QString &date) const;
    Q_INVOKABLE bool closeCash(const QString &date, double counted);
    Q_INVOKABLE QVariantList cashClosings() const;
    Q_INVOKABLE QVariantList bankAccounts() const;
    Q_INVOKABLE bool addBankAccount(const QVariantMap &v);
    Q_INVOKABLE QVariantList bankLines(int accountId) const;
    Q_INVOKABLE bool addBankLine(const QVariantMap &v);
    Q_INVOKABLE QVariantList unreconciledPayments() const;
    Q_INVOKABLE bool reconcileBankLine(int lineId, int paymentId);
    Q_INVOKABLE QVariantList studentSchedule(int studentId) const;
    Q_INVOKABLE bool addScheduleInstallment(int studentId, const QString &label, const QString &dueDate, double amount);
    Q_INVOKABLE bool deleteScheduleInstallment(int id);
''')
edit(hd, '    double oneTimeBilled(int studentId, const QString &from, const QString &to) const;\n',
     '    double oneTimeBilled(int studentId, const QString &from, const QString &to) const;\n    bool periodOpenFor(const QString &dateText) const;\n')

cpp = 'src/core/SchoolApp.cpp'
s = open(cpp, encoding='utf-8').read()
s = s.replace('QStringList SchoolApp::paymentMethods() const { return {"mvola","orange_money","airtel_money","virement","especes"}; }',
              'QStringList SchoolApp::paymentMethods() const\n{\n    QStringList out;\n    QSqlQuery q(m_db.db());\n    if (q.exec("SELECT code FROM payment_methods WHERE is_active=1 ORDER BY rowid")) while (q.next()) out << q.value(0).toString();\n    return out;\n}', 1)
open(cpp, 'w', encoding='utf-8').write(s)
edit(cpp, '    if(amount <= 0.0) return false;\n', '    if(amount <= 0.0) return false;\n    if(!periodOpenFor(v.value("paidAt").toString())) { emit errorOccurred(QStringLiteral("Période comptable clôturée : enregistrement refusé.")); return false; }\n')
edit(cpp, '    const double amount=v.value("amount").toDouble(); if(amount<=0) return false;\n', '    const double amount=v.value("amount").toDouble(); if(amount<=0) return false;\n    if(!periodOpenFor(v.value("date").toString())) { emit errorOccurred(QStringLiteral("Période comptable clôturée : dépense refusée.")); return false; }\n')

s = open(cpp, encoding='utf-8').read()
s += '''
bool SchoolApp::periodOpenFor(const QString &dateText) const
{
    const QString d = dateText.trimmed().isEmpty() ? QDate::currentDate().toString("yyyy-MM-dd") : dateText.trimmed().left(10);
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COUNT(*) FROM accounting_periods WHERE closed=1 AND ? BETWEEN start_date AND end_date");
    q.addBindValue(d);
    return !(q.exec() && q.next() && q.value(0).toInt() > 0);
}

QVariantList SchoolApp::paymentMethodList() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT code,label,is_active FROM payment_methods ORDER BY rowid")) return out;
    while (q.next()) {
        QVariantMap m;
        m["code"] = q.value(0).toString();
        m["label"] = q.value(1).toString();
        m["active"] = q.value(2).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addPaymentMethod(const QString &code, const QString &label)
{
    if (!can("paymentmethods.manage")) return false;
    const QString c = code.trimmed().toLower(), l = label.trimmed();
    if (c.isEmpty() || l.isEmpty() || c.contains(' ')) { emit errorOccurred(QStringLiteral("Code (sans espace) et libellé requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO payment_methods(code,label,is_active) VALUES(?,?,1)");
    q.addBindValue(c);
    q.addBindValue(l);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce moyen de paiement existe déjà.") : q.lastError().text()); return false; }
    audit("create", "payment_method", 0, c);
    emit dataChanged();
    return true;
}

bool SchoolApp::setPaymentMethodActive(const QString &code, bool active)
{
    if (!can("paymentmethods.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE payment_methods SET is_active=? WHERE code=?");
    q.addBindValue(active ? 1 : 0);
    q.addBindValue(code);
    if (!q.exec() || q.numRowsAffected() != 1) return false;
    audit("update", "payment_method", 0, code + (active ? " activé" : " désactivé"));
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::accountingPeriods() const
{
    QVariantList out;
    if (!can("closing.manage") && !can("accounting.write")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,label,start_date,end_date,closed FROM accounting_periods ORDER BY start_date DESC")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["label"] = q.value(1).toString();
        m["startDate"] = q.value(2).toString();
        m["endDate"] = q.value(3).toString();
        m["closed"] = q.value(4).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addAccountingPeriod(const QVariantMap &v)
{
    if (!can("closing.manage")) return false;
    const QString label = v.value("label").toString().trimmed();
    const QDate start = QDate::fromString(v.value("startDate").toString(), "yyyy-MM-dd");
    const QDate end = QDate::fromString(v.value("endDate").toString(), "yyyy-MM-dd");
    if (label.isEmpty() || !start.isValid() || !end.isValid() || end < start) {
        emit errorOccurred(QStringLiteral("Libellé et dates valides (AAAA-MM-JJ, fin après début) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO accounting_periods(label,start_date,end_date,closed) VALUES(?,?,?,0)");
    q.addBindValue(label);
    q.addBindValue(start.toString("yyyy-MM-dd"));
    q.addBindValue(end.toString("yyyy-MM-dd"));
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette période existe déjà.") : q.lastError().text()); return false; }
    audit("create", "accounting_period", q.lastInsertId().toInt(), label);
    emit dataChanged();
    return true;
}

bool SchoolApp::setAccountingPeriodClosed(int id, bool closed)
{
    if (!can("closing.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE accounting_periods SET closed=?, closed_at=? WHERE id=?");
    q.addBindValue(closed ? 1 : 0);
    q.addBindValue(closed ? QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss") : QVariant());
    q.addBindValue(id);
    if (!q.exec() || q.numRowsAffected() != 1) return false;
    audit(closed ? "close" : "reopen", "accounting_period", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::cashMovements(const QString &date) const
{
    QVariantList out;
    if (!can("cash.manage")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,kind,amount,label FROM cash_movements WHERE movement_date=? ORDER BY id");
    q.addBindValue(date.trimmed());
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["kind"] = q.value(1).toString();
        m["amount"] = q.value(2).toDouble();
        m["label"] = q.value(3).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addCashMovement(const QVariantMap &v)
{
    if (!can("cash.manage")) return false;
    const QDate date = QDate::fromString(v.value("date").toString(), "yyyy-MM-dd");
    const QString kind = v.value("kind").toString();
    const double amount = v.value("amount").toDouble();
    const QString label = v.value("label").toString().trimmed();
    if (!date.isValid() || amount <= 0 || label.isEmpty() || !QStringList({"entree", "sortie"}).contains(kind)) {
        emit errorOccurred(QStringLiteral("Date, type, montant (> 0) et libellé requis."));
        return false;
    }
    if (!periodOpenFor(date.toString("yyyy-MM-dd"))) { emit errorOccurred(QStringLiteral("Période comptable clôturée.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO cash_movements(movement_date,kind,amount,label,recorded_by) VALUES(?,?,?,?,?)");
    q.addBindValue(date.toString("yyyy-MM-dd"));
    q.addBindValue(kind);
    q.addBindValue(amount);
    q.addBindValue(label);
    q.addBindValue(m_userId);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "cash_movement", q.lastInsertId().toInt(), kind + " " + label);
    emit dataChanged();
    return true;
}

QVariantMap SchoolApp::cashExpected(const QString &date) const
{
    QVariantMap out;
    if (!can("cash.manage")) return out;
    const QString d = date.trimmed();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE((SELECT SUM(amount) FROM payments WHERE method='especes' AND substr(paid_at,1,10)=?),0) "
              "+ COALESCE((SELECT SUM(amount) FROM cash_movements WHERE movement_date=? AND kind='entree'),0) "
              "- COALESCE((SELECT SUM(amount) FROM cash_movements WHERE movement_date=? AND kind='sortie'),0)");
    q.addBindValue(d); q.addBindValue(d); q.addBindValue(d);
    out["expected"] = q.exec() && q.next() ? q.value(0).toDouble() : 0.0;
    return out;
}

bool SchoolApp::closeCash(const QString &date, double counted)
{
    if (!can("cash.manage")) return false;
    const QDate d = QDate::fromString(date.trimmed(), "yyyy-MM-dd");
    if (!d.isValid() || counted < 0) { emit errorOccurred(QStringLiteral("Date et montant compté valides requis.")); return false; }
    const double expected = cashExpected(d.toString("yyyy-MM-dd")).value("expected").toDouble();
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO cash_closings(closing_date,expected,counted,difference,closed_by) VALUES(?,?,?,?,?) "
              "ON CONFLICT(closing_date) DO UPDATE SET expected=excluded.expected, counted=excluded.counted, "
              "difference=excluded.difference, closed_by=excluded.closed_by");
    q.addBindValue(d.toString("yyyy-MM-dd"));
    q.addBindValue(expected);
    q.addBindValue(counted);
    q.addBindValue(counted - expected);
    q.addBindValue(m_userId);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("close", "cash", 0, d.toString("yyyy-MM-dd") + " écart " + QString::number(counted - expected));
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::cashClosings() const
{
    QVariantList out;
    if (!can("cash.manage")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT closing_date,expected,counted,difference FROM cash_closings ORDER BY closing_date DESC")) return out;
    while (q.next()) {
        QVariantMap m;
        m["date"] = q.value(0).toString();
        m["expected"] = q.value(1).toDouble();
        m["counted"] = q.value(2).toDouble();
        m["difference"] = q.value(3).toDouble();
        out << m;
    }
    return out;
}

QVariantList SchoolApp::bankAccounts() const
{
    QVariantList out;
    if (!can("bank.manage")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT a.id,a.name,COALESCE(a.bank,''),COALESCE(a.last4,''),a.opening_balance, "
                "COALESCE((SELECT SUM(amount) FROM bank_lines WHERE account_id=a.id),0), "
                "(SELECT COUNT(*) FROM bank_lines WHERE account_id=a.id AND payment_id IS NOT NULL), "
                "(SELECT COUNT(*) FROM bank_lines WHERE account_id=a.id) FROM bank_accounts a ORDER BY a.name")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["bank"] = q.value(2).toString();
        m["last4"] = q.value(3).toString();
        m["balance"] = q.value(4).toDouble() + q.value(5).toDouble();
        m["reconciled"] = q.value(6).toInt();
        m["lines"] = q.value(7).toInt();
        out << m;
    }
    return out;
}

bool SchoolApp::addBankAccount(const QVariantMap &v)
{
    if (!can("bank.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const QString last4 = v.value("last4").toString().trimmed();
    if (name.isEmpty() || (!last4.isEmpty() && (last4.size() != 4 || !last4.toInt()))) {
        emit errorOccurred(QStringLiteral("Nom requis ; seuls les 4 derniers chiffres du compte sont enregistrés."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO bank_accounts(name,bank,last4,opening_balance) VALUES(?,?,?,?)");
    q.addBindValue(name);
    q.addBindValue(v.value("bank").toString().trimmed());
    q.addBindValue(last4);
    q.addBindValue(v.value("openingBalance").toDouble());
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce compte existe déjà.") : q.lastError().text()); return false; }
    audit("create", "bank_account", q.lastInsertId().toInt(), name);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::bankLines(int accountId) const
{
    QVariantList out;
    if (!can("bank.manage")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,line_date,label,amount,COALESCE(payment_id,0) FROM bank_lines WHERE account_id=? ORDER BY line_date DESC, id DESC");
    q.addBindValue(accountId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["lineDate"] = q.value(1).toString();
        m["label"] = q.value(2).toString();
        m["amount"] = q.value(3).toDouble();
        m["paymentId"] = q.value(4).toInt();
        out << m;
    }
    return out;
}

bool SchoolApp::addBankLine(const QVariantMap &v)
{
    if (!can("bank.manage")) return false;
    const QDate d = QDate::fromString(v.value("date").toString(), "yyyy-MM-dd");
    const double amount = v.value("amount").toDouble();
    if (!d.isValid() || amount == 0 || v.value("label").toString().trimmed().isEmpty()) {
        emit errorOccurred(QStringLiteral("Date, libellé et montant (non nul, + ou -) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO bank_lines(account_id,line_date,label,amount) VALUES(?,?,?,?)");
    q.addBindValue(v.value("accountId").toInt());
    q.addBindValue(d.toString("yyyy-MM-dd"));
    q.addBindValue(v.value("label").toString().trimmed());
    q.addBindValue(amount);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "bank_line", q.lastInsertId().toInt(), v.value("label").toString());
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::unreconciledPayments() const
{
    QVariantList out;
    if (!can("bank.manage")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT p.id,p.amount,p.method,substr(p.paid_at,1,10),s.last_name || ' ' || s.first_name FROM payments p "
                "JOIN students s ON s.id=p.student_id WHERE p.method<>'especes' "
                "AND p.id NOT IN (SELECT payment_id FROM bank_lines WHERE payment_id IS NOT NULL) ORDER BY p.paid_at DESC")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["amount"] = q.value(1).toDouble();
        m["method"] = q.value(2).toString();
        m["date"] = q.value(3).toString();
        m["label"] = q.value(3).toString() + " · " + q.value(4).toString() + " · " + QString::number(q.value(1).toDouble(), 'f', 0) + " Ar (" + q.value(2).toString() + ")";
        out << m;
    }
    return out;
}

bool SchoolApp::reconcileBankLine(int lineId, int paymentId)
{
    if (!can("bank.manage")) return false;
    QSqlQuery c(m_db.db());
    c.prepare("SELECT ABS(l.amount) = p.amount FROM bank_lines l, payments p WHERE l.id=? AND p.id=? AND l.payment_id IS NULL "
              "AND p.id NOT IN (SELECT payment_id FROM bank_lines WHERE payment_id IS NOT NULL)");
    c.addBindValue(lineId);
    c.addBindValue(paymentId);
    if (!c.exec() || !c.next()) { emit errorOccurred(QStringLiteral("Rapprochement impossible : ligne ou paiement déjà rapproché.")); return false; }
    if (c.value(0).toInt() != 1) { emit errorOccurred(QStringLiteral("Le montant de la ligne ne correspond pas au paiement.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE bank_lines SET payment_id=? WHERE id=?");
    q.addBindValue(paymentId);
    q.addBindValue(lineId);
    if (!q.exec()) return false;
    audit("update", "bank_reconciliation", lineId, "paiement " + QString::number(paymentId));
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::studentSchedule(int studentId) const
{
    QVariantList out;
    if (!canViewStudent(studentId)) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,label,due_date,amount FROM payment_schedules WHERE student_id=? ORDER BY due_date,id");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    QVariantList rows;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["label"] = q.value(1).toString();
        m["dueDate"] = q.value(2).toString();
        m["amount"] = q.value(3).toDouble();
        rows << m;
    }
    QSqlQuery p(m_db.db());
    p.prepare("SELECT COALESCE(SUM(amount),0) FROM payments WHERE student_id=?");
    p.addBindValue(studentId);
    const double paid = p.exec() && p.next() ? p.value(0).toDouble() : 0.0;
    double cumulative = 0;
    for (const QVariant &v : rows) {
        QVariantMap m = v.toMap();
        const double before = cumulative;
        cumulative += m["amount"].toDouble();
        m["status"] = paid >= cumulative ? QStringLiteral("paid") : paid > before ? QStringLiteral("partial") : QStringLiteral("pending");
        out << m;
    }
    return out;
}

bool SchoolApp::addScheduleInstallment(int studentId, const QString &label, const QString &dueDate, double amount)
{
    if (!can("schedule.manage")) return false;
    const QDate d = QDate::fromString(dueDate.trimmed(), "yyyy-MM-dd");
    if (studentId <= 0 || label.trimmed().isEmpty() || !d.isValid() || amount <= 0) {
        emit errorOccurred(QStringLiteral("Élève, libellé, échéance (AAAA-MM-JJ) et montant (> 0) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO payment_schedules(student_id,label,due_date,amount) VALUES(?,?,?,?)");
    q.addBindValue(studentId);
    q.addBindValue(label.trimmed());
    q.addBindValue(d.toString("yyyy-MM-dd"));
    q.addBindValue(amount);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "schedule", q.lastInsertId().toInt(), label);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteScheduleInstallment(int id)
{
    if (!can("schedule.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM payment_schedules WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "schedule", id);
    emit dataChanged();
    return true;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sb = 'qml/components/Sidebar.qml'
edit(sb, '                ["finreports", "Rapports financiers", "📊"],\n',
     '                ["finreports", "Rapports financiers", "📊"],\n                ["treasury", "Caisse, banque et clôtures", "🏦"],\n')
mq = 'qml/Main.qml'
edit(mq, '"finreports":22}', '"finreports":22,"treasury":23}')
edit(mq, '                        FinanceReportsPage {}\n', '                        FinanceReportsPage {}\n                        AccountingExtraPage {}\n')
cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/FinanceReportsPage.qml\n', '        qml/pages/FinanceReportsPage.qml\n        qml/pages/AccountingExtraPage.qml\n')
print("phase 13 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: clôtures de périodes comptables, caisse et clôture journalière, banque et rapprochement, moyens de paiement configurables, échéanciers"

echo ""
echo "Commit créé sur la branche feat/escato-gs-comptabilite-tresorerie."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-comptabilite-tresorerie"
