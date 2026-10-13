#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-frais-ponctuels main
git rm -q --ignore-unmatch install-phase4.sh install-phase5.sh install-phase6.sh install-phase7.sh || true

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
    property var feeTypes: []
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
    function refreshFeeTypes() {
        feeTypes = school.feeTypes()
    }
    Component.onCompleted: { refreshTuitions(); refreshOverview(); refreshFeeTypes() }
    Connections {
        target: school
        function onDataChanged() { root.refreshTuitions(); root.refreshOverview(); root.refreshFeeTypes() }
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
                        visible: root.canEdit
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
                        visible: root.canEdit
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
QML

python3 <<'PY'
def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS fee_types(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            default_amount REAL NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1
        ))",

        R"(CREATE TABLE IF NOT EXISTS one_time_fees(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            fee_type_id INTEGER NOT NULL REFERENCES fee_types(id),
            amount REAL NOT NULL,
            due_date TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            payment_id INTEGER REFERENCES payments(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')
edit(db, 'bool Database::seed()\n{\n', '''bool Database::seed()
{
    if (!exec("INSERT OR IGNORE INTO fee_types(name,default_amount) VALUES ('Frais d''inscription',0),('Uniforme',0),('Frais d''examen',0),('Carte scolaire',0)"))
        return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES ('fees.onetime.manage','Gérer les types de frais ponctuels et les assigner','Finances')"))
        return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES ('fees.onetime.pay','Encaisser les frais ponctuels','Finances')"))
        return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','fees.onetime.manage',1),('enseignant','fees.onetime.manage',0),('eleve','fees.onetime.manage',0),('parent','fees.onetime.manage',0),('comptable','fees.onetime.manage',1),('administrateur','fees.onetime.pay',1),('enseignant','fees.onetime.pay',0),('eleve','fees.onetime.pay',0),('parent','fees.onetime.pay',0),('comptable','fees.onetime.pay',1)"))
        return false;

''')

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE bool setPermission(const QString &role, const QString &permission, bool allowedValue);\n', '''    Q_INVOKABLE bool setPermission(const QString &role, const QString &permission, bool allowedValue);

    Q_INVOKABLE QVariantList feeTypes() const;
    Q_INVOKABLE bool addFeeType(const QVariantMap &v);
    Q_INVOKABLE bool assignOneTimeFeeToClass(int feeTypeId, const QString &className, double amount, const QString &dueDate);
    Q_INVOKABLE QVariantList studentOneTimeFees(int studentId) const;
    Q_INVOKABLE int payOneTimeFee(int feeId, const QString &method, const QString &reference);
''')
edit(hd, '    bool allowed(const QStringList &roles) const;\n', '    bool allowed(const QStringList &roles) const;\n    double oneTimeBilled(int studentId, const QString &from, const QString &to) const;\n')

cpp = 'src/core/SchoolApp.cpp'
edit(cpp, '    double collected = 0;\n', '''    QSqlQuery o(m_db.db());
    o.prepare("SELECT COALESCE(SUM(amount),0) FROM one_time_fees WHERE due_date BETWEEN ? AND ?");
    o.addBindValue(from); o.addBindValue(to);
    if (o.exec() && o.next()) billed += o.value(0).toDouble();
    double collected = 0;
''')
edit(cpp, '            const double sBilled = s.value(3).toDouble();\n',
     '            const double sBilled = s.value(3).toDouble() + oneTimeBilled(s.value(0).toInt(), from, to);\n')

s = open(cpp, encoding='utf-8').read()
s += '''
QVariantList SchoolApp::feeTypes() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name,default_amount FROM fee_types WHERE is_active=1 ORDER BY name")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["amount"] = q.value(2).toDouble();
        out << m;
    }
    return out;
}

bool SchoolApp::addFeeType(const QVariantMap &v)
{
    if (!can("fees.onetime.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const double amount = v.value("amount").toDouble();
    if (name.isEmpty() || amount < 0) {
        emit errorOccurred(QStringLiteral("Nom et montant valides requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO fee_types(name,default_amount) VALUES(?,?)");
    q.addBindValue(name);
    q.addBindValue(amount);
    if (!q.exec()) {
        emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce type de frais existe déjà.") : q.lastError().text());
        return false;
    }
    audit("create", "fee_type", q.lastInsertId().toInt(), name);
    emit dataChanged();
    return true;
}

bool SchoolApp::assignOneTimeFeeToClass(int feeTypeId, const QString &className, double amount, const QString &dueDate)
{
    if (!can("fees.onetime.manage")) return false;
    const QDate due = QDate::fromString(dueDate.trimmed(), "yyyy-MM-dd");
    if (!due.isValid() || amount < 0 || !classes().contains(className)) {
        emit errorOccurred(QStringLiteral("Classe, montant et échéance (AAAA-MM-JJ) valides requis."));
        return false;
    }
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    QSqlQuery q(db);
    q.prepare("INSERT INTO one_time_fees(student_id,fee_type_id,amount,due_date,status) "
              "SELECT id,?,?,?,'pending' FROM students WHERE current_class=? AND deleted_at IS NULL AND graduated_at IS NULL");
    q.addBindValue(feeTypeId);
    q.addBindValue(amount);
    q.addBindValue(due.toString("yyyy-MM-dd"));
    q.addBindValue(className);
    if (!q.exec()) { db.rollback(); emit errorOccurred(q.lastError().text()); return false; }
    const int count = q.numRowsAffected();
    if (count == 0) {
        db.rollback();
        emit errorOccurred(QStringLiteral("Aucun élève inscrit dans cette classe."));
        return false;
    }
    db.commit();
    audit("create", "one_time_fee", feeTypeId, className + " (" + QString::number(count) + " élèves)");
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::studentOneTimeFees(int studentId) const
{
    QVariantList out;
    if (!canViewStudent(studentId)) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT o.id,t.name,o.amount,o.due_date,o.status,o.payment_id FROM one_time_fees o "
              "JOIN fee_types t ON t.id=o.fee_type_id WHERE o.student_id=? ORDER BY o.due_date DESC");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["amount"] = q.value(2).toDouble();
        m["dueDate"] = q.value(3).toString();
        m["status"] = q.value(4).toString();
        m["paymentId"] = q.value(5).toInt();
        out << m;
    }
    return out;
}

int SchoolApp::payOneTimeFee(int feeId, const QString &method, const QString &reference)
{
    if (!can("fees.onetime.pay")) return 0;
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return 0;

    QSqlQuery f(db);
    f.prepare("SELECT o.student_id,o.amount,t.name FROM one_time_fees o JOIN fee_types t ON t.id=o.fee_type_id "
              "WHERE o.id=? AND o.status='pending'");
    f.addBindValue(feeId);
    if (!f.exec() || !f.next()) {
        db.rollback();
        emit errorOccurred(QStringLiteral("Frais introuvable ou déjà payé."));
        return 0;
    }
    const int studentId = f.value(0).toInt();
    const double amount = f.value(1).toDouble();
    const QString name = f.value(2).toString();
    const QString paidAt = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss");

    QSqlQuery p(db);
    p.prepare("INSERT INTO payments(student_id,recorded_by,amount,method,payer_role,reference,paid_at,notes) "
              "VALUES(?,?,?,?,'eleve',?,?,?)");
    p.addBindValue(studentId);
    p.addBindValue(m_userId);
    p.addBindValue(amount);
    p.addBindValue(method);
    p.addBindValue(reference.trimmed());
    p.addBindValue(paidAt);
    p.addBindValue(QStringLiteral("Frais ponctuel : ") + name);
    if (!p.exec()) { db.rollback(); emit errorOccurred(p.lastError().text()); return 0; }
    const int paymentId = p.lastInsertId().toInt();

    const QString year = paidAt.left(4);
    QSqlQuery seq(db);
    seq.prepare("SELECT COALESCE(MAX(CAST(substr(receipt_number,-5) AS INTEGER)),0)+1 FROM payments WHERE receipt_number LIKE ?");
    seq.addBindValue(QStringLiteral("REC-%1-%").arg(year));
    const int next = seq.exec() && seq.next() ? seq.value(0).toInt() : 1;
    QSqlQuery rn(db);
    rn.prepare("UPDATE payments SET receipt_number=? WHERE id=?");
    rn.addBindValue(QStringLiteral("REC-%1-%2").arg(year).arg(next, 5, 10, QLatin1Char('0')));
    rn.addBindValue(paymentId);
    rn.exec();

    QSqlQuery u(db);
    u.prepare("UPDATE one_time_fees SET status='paid', payment_id=? WHERE id=?");
    u.addBindValue(paymentId);
    u.addBindValue(feeId);
    if (!u.exec()) { db.rollback(); emit errorOccurred(u.lastError().text()); return 0; }

    db.commit();
    audit("create", "payment", paymentId, QStringLiteral("frais ponctuel %1").arg(feeId));
    emit dataChanged();
    return paymentId;
}

double SchoolApp::oneTimeBilled(int studentId, const QString &from, const QString &to) const
{
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE(SUM(amount),0) FROM one_time_fees WHERE student_id=? AND due_date BETWEEN ? AND ?");
    q.addBindValue(studentId);
    q.addBindValue(from);
    q.addBindValue(to);
    return q.exec() && q.next() ? q.value(0).toDouble() : 0.0;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sd = 'qml/pages/StudentDetailPage.qml'
edit(sd, '    property var paymentRows: []\n', '    property var paymentRows: []\n    property var oneTimeRows: []\n')
edit(sd, '        paymentRows = school.payments(studentId)\n',
     '        paymentRows = school.payments(studentId)\n        oneTimeRows = school.studentOneTimeFees(studentId)\n')
edit(sd, '''            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: paymentColumn.implicitHeight + 40
''', '''            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: oneTimeColumn.implicitHeight + 40

                ColumnLayout {
                    id: oneTimeColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10

                    Label{text:"Frais ponctuels";font.pixelSize:20;font.bold:true;color:"#0B2A43"}
                    Label {
                        visible: oneTimeRows.length === 0
                        text: "Aucun frais ponctuel assigné à cet élève."
                        color: "#667085"
                    }
                    Repeater {
                        model: oneTimeRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label{text:modelData.name; Layout.fillWidth: true}
                            Label{text:"échéance " + modelData.dueDate; color:"#667085"}
                            Label{text:fmt(modelData.amount); font.bold:true}
                            ComboBox {
                                id: feeMethod
                                visible: modelData.status === "pending"
                                model: school.paymentMethods()
                                Layout.preferredWidth: 150
                            }
                            AppButton {
                                visible: modelData.status === "pending"
                                text: "Encaisser"
                                highlighted: true
                                onClicked: school.payOneTimeFee(modelData.id, feeMethod.currentText, "")
                            }
                            Label {
                                visible: modelData.status === "paid"
                                text: "Payé"
                                color: "#0F9D8F"
                                font.bold: true
                            }
                            AppButton {
                                visible: modelData.status === "paid"
                                text: "🧾 Reçu"
                                onClicked: printer.printReceipt(modelData.paymentId)
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: paymentColumn.implicitHeight + 40
''')

print("phase 7 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: frais ponctuels (inscription, uniforme, examen, carte scolaire), assignation par classe et encaissement avec reçu"

echo ""
echo "Commit créé sur la branche feat/escato-gs-frais-ponctuels."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-frais-ponctuels"
