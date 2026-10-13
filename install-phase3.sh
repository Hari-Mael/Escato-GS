#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-attestations-stats main

cat > qml/pages/DashboardPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ESCATO
import "../components"

ScrollView {
    id: root
    clip: true

    property var stats: ({})

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function refresh() {
        stats = school.monthlyStats()
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        width: root.availableWidth
        spacing: 22

        Label { text: "Tableau de bord"; font.pixelSize: 30; font.bold: true }
        Label { text: "Vue centralisée de l'établissement"; color: "#667085" }

        RowLayout {
            spacing: 15
            StatCard { title: "Élèves"; value: school.studentCount }
            StatCard { title: "Enseignants"; value: school.teacherCount }
            StatCard { title: "Cours"; value: school.courseCount }
            StatCard { title: "Factures en attente"; value: school.pendingInvoiceCount }
        }

        RowLayout {
            spacing: 15
            StatCard { title: "Paiements ce mois"; value: root.fmt(root.stats.paidAmount || 0) }
            StatCard { title: "Factures en retard"; value: String(root.stats.lateCount || 0) }
            StatCard { title: "Reste à recouvrer"; value: root.fmt(root.stats.dueAmount || 0) }
            StatCard { title: "Retards ce mois"; value: String(root.stats.tardinessCount || 0) }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 170
            radius: 16
            color: "#0B2A43"
            Column {
                anchors.fill: parent; anchors.margins: 25; spacing: 10
                Label { text: "Gestion centralisée"; color: "white"; font.pixelSize: 23; font.bold: true }
                Label { text: "Élèves • Enseignants • Cours • Examens • Paiements • Communication"; color: "#D9EAF7" }
                Label { text: "Les modules sont séparés dans le code tout en partageant la même base SQLite."; color: "#B9D7EF" }
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

cpp0 = 'src/core/SchoolApp.cpp'
edit(cpp0, 'matricule="ELV-"+QDateTime::currentDateTime().toString("yyyyMMddhhmmsszzz");',
     'matricule="ELV-"+QDateTime::currentDateTime().toString("yyyyMMddhhmmsszzz")+"-"+QUuid::createUuid().toString(QUuid::Id128).left(4).toUpper();')

db = 'src/core/Database.cpp'
edit(db, '    // Anciennes versions : un compte administrateur codé en dur', '''    if (!exec("UPDATE students SET current_class='TL1' WHERE current_class IN ('T L1','Terminale L1')")) return false;
    if (!exec("UPDATE students SET current_class='TL2' WHERE current_class IN ('T L2','Terminale L2')")) return false;
    if (!exec("UPDATE students SET current_class='TS' WHERE current_class IN ('T S1','T S2','Terminale S')")) return false;

    // Anciennes versions : un compte administrateur codé en dur''')

cpp = 'src/core/SchoolApp.cpp'
edit(cpp, '"Terminale L1","Terminale L2","Terminale S"};', '"TL1","TL2","TS"};')
s = open(cpp, encoding='utf-8').read()
s += '''
QVariantMap SchoolApp::monthlyStats() const
{
    QVariantMap m;
    QSqlQuery p(m_db.db());
    if (p.exec("SELECT COALESCE(SUM(amount),0), COUNT(*) FROM payments "
               "WHERE strftime('%Y-%m', paid_at)=strftime('%Y-%m','now','localtime')") && p.next()) {
        m["paidAmount"] = p.value(0).toDouble();
        m["paidCount"] = p.value(1).toInt();
    }
    QSqlQuery late(m_db.db());
    if (late.exec("SELECT COUNT(*), COALESCE(SUM(amount),0) FROM invoices WHERE status='late'") && late.next()) {
        m["lateCount"] = late.value(0).toInt();
        m["lateAmount"] = late.value(1).toDouble();
    }
    QSqlQuery due(m_db.db());
    if (due.exec("SELECT COALESCE(SUM(amount),0) FROM invoices WHERE status IN ('pending','late')") && due.next())
        m["dueAmount"] = due.value(0).toDouble();
    QSqlQuery tard(m_db.db());
    if (tard.exec("SELECT COUNT(*) FROM tardiness_records "
                  "WHERE strftime('%Y-%m', occurred_at)=strftime('%Y-%m','now','localtime')") && tard.next())
        m["tardinessCount"] = tard.value(0).toInt();
    return m;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QVariantList dashboard() const;\n',
     '    Q_INVOKABLE QVariantList dashboard() const;\n    Q_INVOKABLE QVariantMap monthlyStats() const;\n')

pm_h = 'src/core/PrintManager.h'
edit(pm_h, '    Q_INVOKABLE bool exportPaymentRequestPdf(const QString &path, int studentId);\n',
     '    Q_INVOKABLE bool exportPaymentRequestPdf(const QString &path, int studentId);\n'
     '    Q_INVOKABLE bool printAttestation(int studentId, const QString &kind);\n'
     '    Q_INVOKABLE bool exportAttestationPdf(const QString &path, int studentId, const QString &kind);\n')

pm = 'src/core/PrintManager.cpp'
helpers = '''
QStringList wrapText(Page &pg, const QString &text, double widthPt)
{
    QStringList lines;
    const QFontMetrics fm(pg.p.font(), pg.p.device());
    const int maxWidth = pg.px(widthPt);
    QString current;
    for (const QString &word : text.split(' ', Qt::SkipEmptyParts)) {
        const QString candidate = current.isEmpty() ? word : current + QLatin1Char(' ') + word;
        if (!current.isEmpty() && fm.horizontalAdvance(candidate) > maxWidth) {
            lines << current;
            current = word;
        } else {
            current = candidate;
        }
    }
    if (!current.isEmpty()) lines << current;
    return lines;
}

bool drawAttestation(Page &pg, int studentId, const QString &kind)
{
    QSqlQuery q(QSqlDatabase::database());
    q.prepare("SELECT last_name,first_name,birth_date,birth_place,current_class,matricule FROM students WHERE id=? AND deleted_at IS NULL");
    q.addBindValue(studentId);
    if (!q.exec() || !q.next()) return false;

    const QString lastName = q.value(0).toString();
    const QString firstName = q.value(1).toString();
    const QString birthDate = q.value(2).toString();
    const QString birthPlace = q.value(3).toString();
    const QString currentClass = q.value(4).toString();
    const QString matricule = q.value(5).toString();

    const QDate today = QDate::currentDate();
    const int startYear = today.month() >= 9 ? today.year() : today.year() - 1;
    const QString academicYear = QString("%1 – %2").arg(startYear).arg(startYear + 1);

    QString title = QStringLiteral("ATTESTATION D'INSCRIPTION");
    if (kind == QLatin1String("frequentation")) title = QStringLiteral("ATTESTATION DE FRÉQUENTATION");
    else if (kind == QLatin1String("reussite")) title = QStringLiteral("ATTESTATION DE RÉUSSITE");

    double y = drawOfficialHeader(pg, title);
    QPainter &p = pg.p;
    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 11));
    pg.text(45, y, QStringLiteral("Année scolaire ") + academicYear); y += 34;
    pg.text(45, y, QStringLiteral("Le Frère Directeur de l'établissement certifie que :")); y += 30;
    pg.text(45, y, QStringLiteral("Nom et prénoms : ") + lastName.toUpper() + " " + firstName); y += 22;
    pg.text(45, y, QStringLiteral("Né(e) le : ") + birthDate
            + (birthPlace.isEmpty() ? QString() : QStringLiteral(" à ") + birthPlace)); y += 22;
    pg.text(45, y, QStringLiteral("Matricule : ") + matricule); y += 34;

    QString body = QStringLiteral("est régulièrement inscrit(e) en classe de ") + currentClass
                 + QStringLiteral(" pour l'année scolaire ") + academicYear + QStringLiteral(".");

    if (kind == QLatin1String("frequentation")) {
        QSqlQuery t(QSqlDatabase::database());
        t.prepare("SELECT COUNT(*) FROM tardiness_records WHERE student_id=? AND occurred_at >= ?");
        t.addBindValue(studentId);
        t.addBindValue(QStringLiteral("%1-09-01").arg(startYear));
        const int late = t.exec() && t.next() ? t.value(0).toInt() : 0;
        body += QStringLiteral(" Il/Elle fréquente l'établissement de façon régulière. Retards enregistrés depuis la rentrée : ")
              + QString::number(late) + QStringLiteral(".");
    } else if (kind == QLatin1String("reussite")) {
        QSqlQuery g(QSqlDatabase::database());
        g.prepare("SELECT AVG(g.score*20.0/e.max_score), COUNT(*) FROM grades g JOIN exams e ON e.id=g.exam_id "
                  "WHERE g.student_id=? AND g.score IS NOT NULL AND e.max_score>0");
        g.addBindValue(studentId);
        if (g.exec() && g.next() && g.value(1).toInt() > 0) {
            body = QStringLiteral("a obtenu une moyenne générale de ") + QString::number(g.value(0).toDouble(), 'f', 2)
                 + QStringLiteral("/20 sur l'ensemble des évaluations enregistrées pour l'année scolaire ") + academicYear + QStringLiteral(".");
        } else {
            body = QStringLiteral("n'a encore aucune évaluation enregistrée pour l'année scolaire ") + academicYear + QStringLiteral(".");
        }
    }

    p.setFont(QFont("Arial", 11));
    for (const QString &line : wrapText(pg, body, 500)) { pg.text(45, y, line); y += 18; }
    y += 16;
    for (const QString &line : wrapText(pg, QStringLiteral("La présente attestation est délivrée à l'intéressé(e) pour servir et valoir ce que de droit."), 500)) {
        pg.text(45, y, line); y += 18;
    }
    y += 24;
    pg.text(45, y, QStringLiteral("Fait à Tolagnaro, le ") + today.toString(QStringLiteral("dd/MM/yyyy")));
    y += 60;
    p.setFont(QFont("Arial", 11, QFont::Bold));
    pg.text(340, y, QStringLiteral("Le Frère Directeur"));
    p.setPen(QPen(QColor("#667085"), 0.8));
    p.drawLine(QPoint(pg.px(330), pg.px(y + 50)), QPoint(pg.px(550), pg.px(y + 50)));
    return true;
}
'''
anchor = 'bool PrintManager::printStudentCertificate(int studentId)\n'
edit(pm, anchor, helpers + '\n' + anchor)

s = open(pm, encoding='utf-8').read()
s += '''
bool PrintManager::printAttestation(int studentId, const QString &kind)
{
    QPrinter printer(QPrinter::HighResolution);
    QPrintDialog dlg(&printer);
    if (dlg.exec() != QDialog::Accepted) return false;
    bool ok = false;
    render(printer, [&](Page &pg) { ok = drawAttestation(pg, studentId, kind); });
    return ok;
}

bool PrintManager::exportAttestationPdf(const QString &path, int studentId, const QString &kind)
{
    if (path.isEmpty()) return false;
    QPrinter printer(QPrinter::HighResolution);
    printer.setOutputFormat(QPrinter::PdfFormat);
    printer.setOutputFileName(path);
    bool ok = false;
    render(printer, [&](Page &pg) { ok = drawAttestation(pg, studentId, kind); });
    return ok;
}
'''
open(pm, 'w', encoding='utf-8').write(s)

sd = 'qml/pages/StudentDetailPage.qml'
edit(sd, '                AppButton { text: "🧾 Demande de paiement"; onClicked: printer.printPaymentRequest(studentId) }\n            }\n',
     '''                AppButton { text: "🧾 Demande de paiement"; onClicked: printer.printPaymentRequest(studentId) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "Attestations :"; color: "#667085" }
                AppButton { text: "Inscription"; onClicked: printer.printAttestation(studentId, "inscription") }
                AppButton { text: "Fréquentation"; onClicked: printer.printAttestation(studentId, "frequentation") }
                AppButton { text: "Réussite"; onClicked: printer.printAttestation(studentId, "reussite") }
                Item { Layout.fillWidth: true }
            }
''')
print("phase 3 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: attestations (inscription, fréquentation, réussite), indicateurs du tableau de bord, classes TL1/TL2/TS"

echo ""
echo "Commit créé sur la branche feat/escato-gs-attestations-stats."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-attestations-stats"
