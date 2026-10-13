#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-famille-recus main

cat > qml/pages/FamilyPortal.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    color: "#F4F7FA"

    property var students: []
    property int selectedId: 0
    property var detail: ({})
    property var invoices: []
    property var payments: []

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function reload() {
        students = school.myStudents()
        if (selectedId === 0 && students.length > 0) selectedId = students[0].id
        refresh()
    }
    function refresh() {
        if (selectedId <= 0) { detail = ({}); invoices = []; payments = []; return }
        detail = school.familyStudent(selectedId)
        invoices = school.familyInvoices(selectedId)
        payments = school.familyPayments(selectedId)
    }
    onSelectedIdChanged: refresh()
    Component.onCompleted: reload()
    Connections { target: school; function onDataChanged() { reload() } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Espace famille"; font.pixelSize: 28; font.bold: true; color: "#0B2A43" }
            Item { Layout.fillWidth: true }
            Label { text: school.currentUser; color: "#667085" }
            AppButton { text: "⎋  Déconnexion"; onClicked: school.logout() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                radius: 16
                color: "white"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Label { text: "Mes enfants"; font.pixelSize: 18; font.bold: true; color: "#0B2A43" }
                    Label {
                        visible: students.length === 0
                        text: "Aucun élève n'est rattaché à votre compte. Adressez-vous à l'administration."
                        wrapMode: Text.WordWrap; color: "#667085"; Layout.fillWidth: true
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: students
                        delegate: AppButton {
                            width: ListView.view.width
                            text: modelData.lastName + " " + modelData.firstName + "  (" + modelData.className + ")"
                            highlighted: modelData.id === selectedId
                            onClicked: selectedId = modelData.id
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: "white"
                visible: selectedId > 0

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12

                    Label {
                        text: (detail.firstName || "") + " " + (detail.lastName || "")
                        font.pixelSize: 24; font.bold: true; color: "#0B2A43"
                    }
                    Label {
                        text: "Classe : " + (detail.className || "") + "   •   Matricule : " + (detail.matricule || "")
                        color: "#667085"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Factures et échéances"; font.pixelSize: 18; font.bold: true; color: "#0B2A43"; Layout.fillWidth: true }
                        AppButton { text: "🖨 Demande de paiement"; onClicked: printer.printPaymentRequest(selectedId) }
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 170
                        clip: true
                        model: invoices
                        delegate: RowLayout {
                            width: ListView.view.width
                            Label { text: modelData.month; Layout.preferredWidth: 140 }
                            Label { text: "échéance " + modelData.dueDate; color: "#667085"; Layout.fillWidth: true }
                            Label { text: fmt(modelData.amount); font.bold: true }
                            Label {
                                text: modelData.status === "paid" ? "Payé" : modelData.status === "late" ? "En retard" : "À payer"
                                color: modelData.status === "paid" ? "#0F9D8F" : "#C62828"
                                Layout.preferredWidth: 90
                            }
                        }
                    }

                    Label { text: "Paiements et reçus"; font.pixelSize: 18; font.bold: true; color: "#0B2A43" }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: payments
                        delegate: RowLayout {
                            width: ListView.view.width
                            Label { text: modelData.paidAt; Layout.preferredWidth: 160 }
                            Label { text: modelData.method; color: "#667085"; Layout.fillWidth: true }
                            Label { text: fmt(modelData.amount); font.bold: true }
                            AppButton { text: "🧾 Reçu"; onClicked: printer.printReceipt(modelData.id) }
                        }
                    }
                }
            }
        }
    }
}
QML

cat > qml/pages/StudentDetailPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    property int studentId: 0
    signal back()

    property var info: ({})
    property var guardianRows: []
    property var parentRows: []
    property var paymentRows: []

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function refresh() {
        info = school.student(studentId)
        guardianRows = school.guardians(studentId)
        parentRows = school.parentLinks(studentId)
        paymentRows = school.payments(studentId)
    }
    onStudentIdChanged: refresh()
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Fiche élève"; font.pixelSize: 28; font.bold: true }
                Item { Layout.fillWidth: true }
                AppButton { text: "← Retour"; onClicked: back() }
                AppButton { text: "🖨 Liste"; onClicked: printer.printStudentList(info.className) }
                AppButton { text: "🪪 Carte élève"; onClicked: printer.printStudentCard(studentId) }
                AppButton { text: "🖨 Certificat"; onClicked: printer.printStudentCertificate(studentId) }
                AppButton { text: "🧾 Demande de paiement"; onClicked: printer.printPaymentRequest(studentId) }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: infoColumn.implicitHeight + 50

                Column {
                    id: infoColumn
                    x: 25; y: 25
                    width: parent.width - 50
                    spacing: 12
                    Label{text:info.firstName+" "+info.lastName; font.pixelSize:28;font.bold:true;color:"#0B2A43"}
                    Label{text:"Matricule : "+info.matricule}
                    Label{text:"Classe : "+info.className}
                    Label{text:"Date d'entrée : "+info.entryDate}
                    Label{text:"Date de naissance : "+info.birthDate+" — "+info.birthPlace}
                    Label{text:"Téléphone parent : "+info.parentPhone}
                    Label{text:"E-mail parent : "+info.parentEmail}
                    Label{text:"Adresse : "+info.address}
                    Label{text:"Ancienne école : "+info.previousSchool}
                    Label{text:"Projet : "+info.desiredCareer}
                    Label{text:"Paiements manqués consécutifs : "+info.missedPayments}
                    Label{text:"Statut du compte : "+info.accountStatus}
                    Row {
                        spacing: 8
                        AppButton{text:"Diplômé";onClicked:school.graduateStudent(studentId)}
                        AppButton{text:"Bloquer";onClicked:school.blockStudent(studentId,"Blocage administratif")}
                        AppButton{text:"Débloquer";onClicked:school.unblockStudent(studentId)}
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: guardianColumn.implicitHeight + 40

                ColumnLayout {
                    id: guardianColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10

                    Label{text:"Parents et tuteurs";font.pixelSize:20;font.bold:true;color:"#0B2A43"}
                    Repeater {
                        model: guardianRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: (modelData.isPrimary ? "★ " : "") + modelData.fullName + " — " + modelData.relation
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            Label{text:modelData.phone; color:"#667085"}
                            AppButton{text:"Retirer"; onClicked: school.removeGuardian(modelData.linkId)}
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        AppTextField{id:gName; placeholderText:"Nom complet"; Layout.fillWidth:true}
                        AppTextField{id:gRelation; placeholderText:"Lien (père, mère…)"; Layout.preferredWidth:160}
                        AppTextField{id:gPhone; placeholderText:"Téléphone"; Layout.preferredWidth:140}
                        CheckBox{id:gPrimary; text:"Principal"}
                        AppButton{
                            text:"Ajouter"; highlighted:true
                            onClicked: {
                                if (school.addGuardian(studentId, {fullName:gName.text, relation:gRelation.text, phone:gPhone.text, isPrimary:gPrimary.checked})) {
                                    gName.text=""; gRelation.text=""; gPhone.text=""; gPrimary.checked=false
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: parentColumn.implicitHeight + 40

                ColumnLayout {
                    id: parentColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10

                    Label{text:"Accès famille (compte parent)";font.pixelSize:20;font.bold:true;color:"#0B2A43"}
                    Label {
                        text: "Créez le compte parent dans Comptes / sécurité, puis rattachez-le ici par son adresse e-mail."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Repeater {
                        model: parentRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: modelData.name + " — " + modelData.email
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            AppButton{text:"Retirer l'accès"; onClicked: school.unlinkParent(modelData.linkId)}
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        AppTextField{id:parentEmail; placeholderText:"E-mail du compte parent"; Layout.fillWidth:true}
                        AppButton{
                            text:"Lier le compte"; highlighted:true
                            onClicked: { if (school.linkParentByEmail(studentId, parentEmail.text)) parentEmail.text = "" }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: paymentColumn.implicitHeight + 40

                ColumnLayout {
                    id: paymentColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10

                    Label{text:"Paiements";font.pixelSize:20;font.bold:true;color:"#0B2A43"}
                    Label {
                        visible: paymentRows.length === 0
                        text: "Aucun paiement enregistré pour cet élève."
                        color: "#667085"
                    }
                    Repeater {
                        model: paymentRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label{text:modelData.paidAt; Layout.preferredWidth: 170}
                            Label{text:modelData.method; color:"#667085"; Layout.fillWidth: true}
                            Label{text:fmt(modelData.amount); font.bold:true}
                            AppButton{text:"🧾 Reçu"; onClicked: printer.printReceipt(modelData.id)}
                        }
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
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS parent_student_links(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parent_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            UNIQUE(parent_user_id, student_id)
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')
edit(db, '    // Anciennes versions : un compte administrateur codé en dur', '''    if (!columnExists(QStringLiteral("payments"), QStringLiteral("receipt_number"))
        && !exec("ALTER TABLE payments ADD COLUMN receipt_number TEXT"))
        return false;
    if (!exec("UPDATE payments SET receipt_number='REC-'||substr(paid_at,1,4)||'-'||printf('%05d',"
              "(SELECT COUNT(*) FROM payments p2 WHERE substr(p2.paid_at,1,4)=substr(payments.paid_at,1,4) AND p2.id<=payments.id)) "
              "WHERE receipt_number IS NULL"))
        return false;

    // Anciennes versions : un compte administrateur codé en dur''')

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE bool removeGuardian(int linkId);\n', '''    Q_INVOKABLE bool removeGuardian(int linkId);

    Q_INVOKABLE QVariantList parentLinks(int studentId) const;
    Q_INVOKABLE bool linkParentByEmail(int studentId, const QString &email);
    Q_INVOKABLE bool unlinkParent(int linkId);
    Q_INVOKABLE QVariantList myStudents() const;
    Q_INVOKABLE QVariantMap familyStudent(int studentId) const;
    Q_INVOKABLE QVariantList familyInvoices(int studentId) const;
    Q_INVOKABLE QVariantList familyPayments(int studentId) const;
    Q_INVOKABLE QVariantMap familyBulletin(int studentId, const QString &term) const;
''')
edit(hd, '    QString m_role;\n', '    QString m_role;\n\n    bool canViewStudent(int studentId) const;\n')

cpp = 'src/core/SchoolApp.cpp'
edit(cpp, '    const int pid=q.lastInsertId().toInt();\n', '''    const int pid=q.lastInsertId().toInt();
    {
        const QString year = paidAt.left(4);
        QSqlQuery seq(db);
        seq.prepare("SELECT COALESCE(MAX(CAST(substr(receipt_number,-5) AS INTEGER)),0)+1 FROM payments WHERE receipt_number LIKE ?");
        seq.addBindValue(QStringLiteral("REC-%1-%").arg(year));
        const int next = seq.exec() && seq.next() ? seq.value(0).toInt() : 1;
        QSqlQuery rn(db);
        rn.prepare("UPDATE payments SET receipt_number=? WHERE id=?");
        rn.addBindValue(QStringLiteral("REC-%1-%2").arg(year).arg(next, 5, 10, QLatin1Char('0')));
        rn.addBindValue(pid);
        rn.exec();
    }
''')

s = open(cpp, encoding='utf-8').read()
s += '''
bool SchoolApp::canViewStudent(int studentId) const
{
    if (m_userId <= 0) return false;
    if (allowed({"administrateur", "enseignant", "comptable"})) return true;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT EXISTS(SELECT 1 FROM parent_student_links WHERE parent_user_id=? AND student_id=?) "
              "OR EXISTS(SELECT 1 FROM students WHERE id=? AND user_id=?)");
    q.addBindValue(m_userId); q.addBindValue(studentId);
    q.addBindValue(studentId); q.addBindValue(m_userId);
    return q.exec() && q.next() && q.value(0).toInt() == 1;
}

QVariantList SchoolApp::parentLinks(int studentId) const
{
    QVariantList out;
    if (!allowed({"administrateur"})) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT l.id,u.id,u.name,u.email FROM parent_student_links l "
              "JOIN users u ON u.id=l.parent_user_id WHERE l.student_id=? AND u.deleted_at IS NULL ORDER BY u.name");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["linkId"] = q.value(0).toInt();
        m["parentId"] = q.value(1).toInt();
        m["name"] = q.value(2).toString();
        m["email"] = q.value(3).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::linkParentByEmail(int studentId, const QString &email)
{
    if (!allowed({"administrateur"})) return false;
    QSqlQuery u(m_db.db());
    u.prepare("SELECT id FROM users WHERE lower(email)=lower(?) AND role='parent' AND deleted_at IS NULL");
    u.addBindValue(email.trimmed());
    if (!u.exec() || !u.next()) {
        emit errorOccurred(QStringLiteral("Aucun compte parent avec cette adresse e-mail. Créez-le d'abord dans Comptes / sécurité."));
        return false;
    }
    QSqlQuery l(m_db.db());
    l.prepare("INSERT OR IGNORE INTO parent_student_links(parent_user_id,student_id) VALUES(?,?)");
    l.addBindValue(u.value(0)); l.addBindValue(studentId);
    if (!l.exec()) { emit errorOccurred(l.lastError().text()); return false; }
    audit("link", "parent", u.value(0).toInt(), QStringLiteral("élève %1").arg(studentId));
    emit dataChanged();
    return true;
}

bool SchoolApp::unlinkParent(int linkId)
{
    if (!allowed({"administrateur"})) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM parent_student_links WHERE id=?");
    q.addBindValue(linkId);
    if (!q.exec()) return false;
    audit("unlink", "parent", linkId);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::myStudents() const
{
    QVariantList out;
    if (m_userId <= 0) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT s.id,s.matricule,s.last_name,s.first_name,s.current_class FROM students s "
              "WHERE s.deleted_at IS NULL AND (s.id IN (SELECT student_id FROM parent_student_links WHERE parent_user_id=?) "
              "OR s.user_id=?) ORDER BY s.last_name,s.first_name");
    q.addBindValue(m_userId); q.addBindValue(m_userId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["matricule"] = q.value(1).toString();
        m["lastName"] = q.value(2).toString();
        m["firstName"] = q.value(3).toString();
        m["className"] = q.value(4).toString();
        out << m;
    }
    return out;
}

QVariantMap SchoolApp::familyStudent(int studentId) const
{
    if (!canViewStudent(studentId)) return {};
    return student(studentId);
}

QVariantList SchoolApp::familyInvoices(int studentId) const
{
    if (!canViewStudent(studentId)) return {};
    return studentInvoices(studentId);
}

QVariantList SchoolApp::familyPayments(int studentId) const
{
    if (!canViewStudent(studentId)) return {};
    return payments(studentId);
}

QVariantMap SchoolApp::familyBulletin(int studentId, const QString &term) const
{
    if (!canViewStudent(studentId)) return {};
    return bulletin(studentId, term);
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

pm_h = 'src/core/PrintManager.h'
edit(pm_h, '    Q_INVOKABLE bool exportStudentCardPdf(const QString &path, int studentId);\n',
     '    Q_INVOKABLE bool exportStudentCardPdf(const QString &path, int studentId);\n'
     '    Q_INVOKABLE bool printReceipt(int paymentId);\n'
     '    Q_INVOKABLE bool exportReceiptPdf(const QString &path, int paymentId);\n'
     '    Q_INVOKABLE bool printPaymentRequest(int studentId);\n'
     '    Q_INVOKABLE bool exportPaymentRequestPdf(const QString &path, int studentId);\n')

pm = 'src/core/PrintManager.cpp'
edit(pm, '#include <QRectF>\n', '#include <QRectF>\n#include <QLocale>\n#include <QVector>\n#include <QPair>\n')

helpers = '''
QString methodLabel(const QString &method)
{
    if (method == QLatin1String("mvola")) return QStringLiteral("Mvola");
    if (method == QLatin1String("orange_money")) return QStringLiteral("Orange Money");
    if (method == QLatin1String("airtel_money")) return QStringLiteral("Airtel Money");
    if (method == QLatin1String("virement")) return QStringLiteral("Virement bancaire");
    if (method == QLatin1String("especes")) return QStringLiteral("Espèces");
    return method;
}

QString formatAr(double amount)
{
    return QLocale(QLocale::French).toString(amount, 'f', 0) + QStringLiteral(" Ar");
}

void renderSized(QPrinter &printer, QPageSize::PageSizeId size, const std::function<void(Page &)> &draw)
{
    printer.setPageSize(QPageSize(size));
    printer.setFullPage(true);
    QPainter p(&printer);
    if (!p.isActive()) return;
    Page pg(printer, p);
    draw(pg);
    p.end();
}

bool drawReceipt(Page &pg, int paymentId)
{
    QSqlQuery q(QSqlDatabase::database());
    q.prepare("SELECT p.receipt_number,p.amount,p.method,p.reference,p.paid_at,s.matricule,s.last_name,s.first_name,"
              "s.current_class,COALESCE(u.name,'') FROM payments p JOIN students s ON s.id=p.student_id "
              "LEFT JOIN users u ON u.id=p.recorded_by WHERE p.id=?");
    q.addBindValue(paymentId);
    if (!q.exec() || !q.next()) return false;

    const QString number = q.value(0).toString();
    const double amount = q.value(1).toDouble();
    const QString method = methodLabel(q.value(2).toString());
    const QString reference = q.value(3).toString();
    const QString paidAt = q.value(4).toString().left(10);
    const QString matricule = q.value(5).toString();
    const QString fullName = q.value(6).toString().toUpper() + " " + q.value(7).toString();
    const QString currentClass = q.value(8).toString();
    const QString recordedBy = q.value(9).toString();

    QPainter &p = pg.p;
    const double left = 30, right = 390;

    p.setPen(QPen(QColor("#D5DEE3"), 1.0));
    p.setBrush(Qt::NoBrush);
    p.drawRoundedRect(QRectF(pg.px(20), pg.px(20), pg.px(380), pg.px(555)), pg.px(10), pg.px(10));

    const QPixmap logo(":/assets/logo.png");
    if (!logo.isNull())
        p.drawPixmap(QRect(pg.px(left), pg.px(35), pg.px(48), pg.px(48)),
                     logo.scaled(pg.px(48), pg.px(48), Qt::KeepAspectRatio, Qt::SmoothTransformation));

    p.setPen(QColor("#0F9D8F"));
    p.setFont(QFont("Arial", 16, QFont::Bold));
    pg.text(90, 58, QStringLiteral("ESCATO GS"));
    p.setPen(QColor("#667085"));
    p.setFont(QFont("Arial", 11));
    pg.text(90, 76, QStringLiteral("Reçu de paiement"));

    p.setPen(QPen(QColor("#0F9D8F"), 1.2));
    p.setBrush(QColor("#E6F6F4"));
    p.drawRoundedRect(QRectF(pg.px(262), pg.px(35), pg.px(128), pg.px(42)), pg.px(8), pg.px(8));
    p.setBrush(Qt::NoBrush);
    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 8));
    pg.text(270, 50, QStringLiteral("N° de reçu"));
    p.setFont(QFont("Arial", 10, QFont::Bold));
    pg.text(270, 68, number);

    p.setPen(QPen(QColor("#E1E8EF"), 1.0));
    p.drawLine(QPoint(pg.px(left), pg.px(100)), QPoint(pg.px(right), pg.px(100)));

    const QVector<QPair<QString, QString>> rows = {
        {QStringLiteral("Élève"), fullName},
        {QStringLiteral("Matricule"), matricule},
        {QStringLiteral("Classe"), currentClass},
        {QStringLiteral("Date de paiement"), paidAt},
        {QStringLiteral("Mode de paiement"), method},
        {QStringLiteral("Référence"), reference.isEmpty() ? QStringLiteral("—") : reference},
        {QStringLiteral("Enregistré par"), recordedBy.isEmpty() ? QStringLiteral("—") : recordedBy}
    };
    double y = 125;
    for (const auto &row : rows) {
        p.setPen(QColor("#667085"));
        p.setFont(QFont("Arial", 10));
        pg.text(left, y, row.first);
        p.setPen(QColor("#0B2A43"));
        p.setFont(QFont("Arial", 11, QFont::Bold));
        pg.cell(165, y, 215, row.second);
        y += 26;
    }

    y += 10;
    p.setPen(Qt::NoPen);
    p.setBrush(QColor("#0F9D8F"));
    p.drawRoundedRect(QRectF(pg.px(left), pg.px(y), pg.px(360), pg.px(50)), pg.px(10), pg.px(10));
    p.setPen(Qt::white);
    p.setFont(QFont("Arial", 10));
    pg.text(left + 16, y + 19, QStringLiteral("Montant payé"));
    p.setFont(QFont("Arial", 18, QFont::Bold));
    pg.text(left + 16, y + 41, formatAr(amount));

    const double sigY = 455;
    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 10, QFont::Bold));
    pg.text(270, sigY, QStringLiteral("Le comptable"));
    p.setPen(QPen(QColor("#667085"), 0.8));
    p.drawLine(QPoint(pg.px(262), pg.px(sigY + 60)), QPoint(pg.px(390), pg.px(sigY + 60)));
    p.setPen(QColor("#667085"));
    p.setFont(QFont("Arial", 8));
    pg.text(270, sigY + 74, QStringLiteral("Signature et cachet"));

    p.setFont(QFont("Arial", 9));
    pg.text(left, 520, QStringLiteral("Ce reçu fait foi de paiement."));
    pg.text(left, 534, QStringLiteral("Merci de conserver ce document."));
    return true;
}

bool drawPaymentRequest(Page &pg, int studentId)
{
    QSqlQuery s(QSqlDatabase::database());
    s.prepare("SELECT matricule,last_name,first_name,current_class,parent_phone FROM students WHERE id=? AND deleted_at IS NULL");
    s.addBindValue(studentId);
    if (!s.exec() || !s.next()) return false;

    QSqlQuery q(QSqlDatabase::database());
    q.prepare("SELECT period_month,due_date,amount,status FROM invoices WHERE student_id=? ORDER BY due_date");
    q.addBindValue(studentId);
    if (!q.exec()) return false;

    double y = drawOfficialHeader(pg, QStringLiteral("DEMANDE DE PAIEMENT"));
    QPainter &p = pg.p;
    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 11));
    pg.text(45, y, QStringLiteral("Élève : ") + s.value(1).toString().toUpper() + " " + s.value(2).toString()); y += 22;
    pg.text(45, y, QStringLiteral("Matricule : ") + s.value(0).toString()); y += 22;
    pg.text(45, y, QStringLiteral("Classe : ") + s.value(3).toString()); y += 22;
    pg.text(45, y, QStringLiteral("Téléphone : ") + s.value(4).toString()); y += 34;

    p.setFont(QFont("Arial", 10, QFont::Bold));
    pg.text(45, y, QStringLiteral("Mois")); pg.text(190, y, QStringLiteral("Échéance"));
    pg.text(340, y, QStringLiteral("Montant")); pg.text(470, y, QStringLiteral("Statut"));
    y += 8;
    p.setPen(QPen(QColor("#D5DEE3"), 0.8));
    p.drawLine(QPoint(pg.px(45), pg.px(y)), QPoint(pg.px(550), pg.px(y)));
    y += 18;

    double due = 0;
    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 10));
    while (q.next()) {
        const QString status = q.value(3).toString();
        const double amount = q.value(2).toDouble();
        if (status != QLatin1String("paid")) due += amount;
        pg.cell(45, y, 130, q.value(0).toString());
        pg.cell(190, y, 130, q.value(1).toString());
        pg.cell(340, y, 120, formatAr(amount));
        pg.cell(470, y, 90, status == QLatin1String("paid") ? QStringLiteral("Payé")
                           : status == QLatin1String("late") ? QStringLiteral("En retard")
                           : QStringLiteral("À payer"));
        y += 20;
    }

    y += 10;
    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 13, QFont::Bold));
    pg.text(45, y, QStringLiteral("Total restant dû : ") + formatAr(due));

    const double sigY = y + 90;
    p.setFont(QFont("Arial", 10, QFont::Bold));
    pg.text(370, sigY, QStringLiteral("Le comptable"));
    p.setPen(QPen(QColor("#667085"), 0.8));
    p.drawLine(QPoint(pg.px(360), pg.px(sigY + 60)), QPoint(pg.px(550), pg.px(sigY + 60)));
    return true;
}
'''
anchor = 'bool PrintManager::printStudentCertificate(int studentId)\n'
edit(pm, anchor, helpers + '\n' + anchor)

s = open(pm, encoding='utf-8').read()
s += '''
bool PrintManager::printReceipt(int paymentId)
{
    QPrinter printer(QPrinter::HighResolution);
    QPrintDialog dlg(&printer);
    if (dlg.exec() != QDialog::Accepted) return false;
    bool ok = false;
    renderSized(printer, QPageSize::A5, [&](Page &pg) { ok = drawReceipt(pg, paymentId); });
    return ok;
}

bool PrintManager::exportReceiptPdf(const QString &path, int paymentId)
{
    if (path.isEmpty()) return false;
    QPrinter printer(QPrinter::HighResolution);
    printer.setOutputFormat(QPrinter::PdfFormat);
    printer.setOutputFileName(path);
    bool ok = false;
    renderSized(printer, QPageSize::A5, [&](Page &pg) { ok = drawReceipt(pg, paymentId); });
    return ok;
}

bool PrintManager::printPaymentRequest(int studentId)
{
    QPrinter printer(QPrinter::HighResolution);
    QPrintDialog dlg(&printer);
    if (dlg.exec() != QDialog::Accepted) return false;
    bool ok = false;
    render(printer, [&](Page &pg) { ok = drawPaymentRequest(pg, studentId); });
    return ok;
}

bool PrintManager::exportPaymentRequestPdf(const QString &path, int studentId)
{
    if (path.isEmpty()) return false;
    QPrinter printer(QPrinter::HighResolution);
    printer.setOutputFormat(QPrinter::PdfFormat);
    printer.setOutputFileName(path);
    bool ok = false;
    render(printer, [&](Page &pg) { ok = drawPaymentRequest(pg, studentId); });
    return ok;
}
'''
open(pm, 'w', encoding='utf-8').write(s)

mq = 'qml/Main.qml'
edit(mq, 'sourceComponent: school.loggedIn ? appComponent : (school.needsSetup ? setupComponent : loginComponent)',
     'sourceComponent: school.loggedIn ? (school.currentRole === "parent" || school.currentRole === "eleve" ? familyComponent : appComponent) : (school.needsSetup ? setupComponent : loginComponent)')
edit(mq, '    Component {\n        id: setupComponent\n        SetupPage {}\n    }\n',
     '    Component {\n        id: setupComponent\n        SetupPage {}\n    }\n\n    Component {\n        id: familyComponent\n        FamilyPortal {}\n    }\n')

cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/SettingsPage.qml\n', '        qml/pages/SettingsPage.qml\n        qml/pages/FamilyPortal.qml\n')
print("phase 2 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: espace famille (parents et élèves en lecture seule), demandes de paiement, reçus A5 numérotés"

echo ""
echo "Commit créé sur la branche feat/escato-gs-famille-recus."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-famille-recus"
