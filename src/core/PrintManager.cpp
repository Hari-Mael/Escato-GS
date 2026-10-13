#include "PrintManager.h"
#include <QPrinter>
#include <QPrintDialog>
#include <QPainter>
#include <QPageSize>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QPixmap>
#include <QFontMetrics>
#include <QDialog>
#include <QDate>
#include <functional>
#include <QFile>
#include <QColor>
#include <QFont>
#include <QRectF>
#include <QLocale>
#include <QVector>
#include <QPair>
#include "third_party/qrcodegen/qrcodegen.hpp"

namespace {

// Toute la mise en page est exprimée en points (A4 = 595 x 842). Elle est convertie en pixels
// périphérique via K = résolution / 72, ce qui garde texte (en pt) et coordonnées cohérents
// quelle que soit la résolution de l'imprimante ou du PDF.
struct Page
{
    QPrinter &printer;
    QPainter &p;
    double k;
    Page(QPrinter &pr, QPainter &pa) : printer(pr), p(pa), k(pr.resolution() / 72.0) {}
    int px(double v) const { return qRound(v * k); }
    void text(double x, double y, const QString &t) { p.drawText(px(x), px(y), t); }
    void cell(double x, double y, double w, const QString &t)
    {
        p.drawText(px(x), px(y), QFontMetrics(p.font(), p.device()).elidedText(t, Qt::ElideRight, px(w)));
    }
};

// En-tête officiel utilisé par les documents administratifs imprimés par ESCATO.
// Le logo fourni par l'établissement est embarqué dans l'exécutable sous :/assets/logo.png.
double drawOfficialHeader(Page &pg, const QString &documentTitle)
{
    QPainter &p = pg.p;
    const double left = 45, right = 555, top = 35;

    const QPixmap logo(":/assets/logo.png");
    if (!logo.isNull()) {
        const int size = pg.px(82);
        p.drawPixmap(pg.px(left), pg.px(top), logo.scaled(size, size, Qt::KeepAspectRatio, Qt::SmoothTransformation));
    }

    p.setPen(Qt::black);
    p.setFont(QFont("Arial", 13, QFont::Bold));
    pg.text(left + 95, top + 12, "Ecole Sacré-Cœur");

    p.setFont(QFont("Arial", 9));
    pg.text(left + 95, top + 27, "Anosy");
    pg.text(left + 95, top + 41, "BP 85");
    pg.text(left + 95, top + 55, "Tél: 0345281271");
    pg.text(left + 95, top + 69, "e-mail : escafor@yahoo.com");
    pg.text(left + 95, top + 83, "Tolagnaro");

    p.setFont(QFont("Arial", 8));
    pg.cell(380, top + 8, right - 380, "Autorisation d'ouverture");
    pg.cell(380, top + 22, right - 380, "N° : 127 / 2024 – MEN");
    pg.cell(380, top + 36, right - 380, "Du 15 Juillet 2024");

    p.setPen(QPen(QColor("#B7B7B7"), 1));
    p.drawLine(pg.px(left), pg.px(top + 108), pg.px(right), pg.px(top + 108));

    p.setPen(Qt::black);
    p.setFont(QFont("Arial", 16, QFont::Bold));
    pg.text(left, top + 136, documentTitle);

    return top + 167;
}

void drawFooter(Page &pg)
{
    pg.p.setPen(QPen(QColor("#B7B7B7"), 1));
    pg.p.drawLine(pg.px(45), pg.px(805), pg.px(555), pg.px(805));
    pg.p.setPen(QColor("#555555"));
    pg.p.setFont(QFont("Arial", 8));
    pg.text(45, 823, "ESCATO — Ecole Sacré-Cœur — Document administratif");
}

struct Column { double x, w; QString title; };

// Tableau paginé : en-tête officiel + titres de colonnes répétés sur chaque page.
void drawTable(Page &pg, const QString &title, const QList<Column> &cols, QSqlQuery &q)
{
    auto startPage = [&]() {
        double y = drawOfficialHeader(pg, title);
        pg.p.setPen(Qt::black);
        pg.p.setFont(QFont("Arial", 9, QFont::Bold));
        for (const auto &c : cols) pg.cell(c.x, y, c.w, c.title);
        pg.p.setFont(QFont("Arial", 9));
        return y + 22;
    };

    double y = startPage();
    while (q.next()) {
        if (y > 790) {
            drawFooter(pg);
            pg.printer.newPage();
            y = startPage();
        }
        for (int i = 0; i < cols.size(); ++i)
            pg.cell(cols[i].x, y, cols[i].w, q.value(i).toString());
        y += 20;
    }
    drawFooter(pg);
}

void drawStudents(Page &pg, const QString &className)
{
    QSqlQuery q(QSqlDatabase::database());
    if (className.isEmpty()) {
        q.exec("SELECT matricule,last_name,first_name,current_class,parent_phone FROM students "
               "WHERE graduated_at IS NULL AND deleted_at IS NULL ORDER BY current_class,last_name");
    } else {
        q.prepare("SELECT matricule,last_name,first_name,current_class,parent_phone FROM students "
                  "WHERE current_class=? AND graduated_at IS NULL AND deleted_at IS NULL ORDER BY last_name");
        q.addBindValue(className);
        q.exec();
    }
    const QString title = className.isEmpty() ? QStringLiteral("LISTE DES ÉLÈVES")
                                              : QStringLiteral("LISTE DES ÉLÈVES — ") + className;
    drawTable(pg, title, {
        {45, 105, "Matricule"}, {155, 105, "Nom"}, {265, 110, "Prénom"},
        {380, 70, "Classe"}, {455, 100, "Téléphone parent"}
    }, q);
}

void drawTeachers(Page &pg)
{
    QSqlQuery q(QSqlDatabase::database());
    q.exec("SELECT u.name,u.email,t.identity_number,t.contact,t.subject "
           "FROM users u LEFT JOIN teacher_profiles t ON t.user_id=u.id "
           "WHERE u.role='enseignant' AND u.deleted_at IS NULL ORDER BY u.name");
    drawTable(pg, QStringLiteral("LISTE DES ENSEIGNANTS"), {
        {45, 100, "Nom"}, {150, 130, "Email"}, {285, 75, "CIN"},
        {365, 85, "Téléphone"}, {455, 100, "Matière"}
    }, q);
}

// Reproduction fidèle du formulaire papier « CERTIFICAT DE SCOLARITE » de l'établissement,
// avec deux champs auto-remplis absents du formulaire papier d'origine : le numéro matricule
// et la date d'inscription (entry_date), en plus des champs déjà présents sur le papier.
void drawCheckbox(Page &pg, double x, double y, const QString &label)
{
    const int s = pg.px(9);
    pg.p.drawRect(pg.px(x), pg.px(y) - s, s, s);
    pg.text(x + 14, y, label);
}

bool drawCertificate(Page &pg, int studentId)
{
    QSqlQuery q(QSqlDatabase::database());
    q.prepare("SELECT matricule,last_name,first_name,birth_date,birth_place,father_name,mother_name,"
              "current_class,previous_class,entry_date FROM students WHERE id=? AND deleted_at IS NULL");
    q.addBindValue(studentId);
    if (!q.exec() || !q.next()) return false;

    const QString matricule = q.value(0).toString();
    const QString lastName = q.value(1).toString();
    const QString firstName = q.value(2).toString();
    const QString birthDate = q.value(3).toString();
    const QString birthPlace = q.value(4).toString();
    const QString fatherName = q.value(5).toString();
    const QString motherName = q.value(6).toString();
    const QString currentClass = q.value(7).toString();
    const QString previousClass = q.value(8).toString();
    const QString entryDate = q.value(9).toString();

    const QDate today = QDate::currentDate();
    const int startYear = today.month() >= 9 ? today.year() : today.year() - 1;
    const QString academicYear = QString("%1 – %2").arg(startYear).arg(startYear + 1);

    double y = drawOfficialHeader(pg, "CERTIFICAT DE SCOLARITE");
    pg.p.setFont(QFont("Arial", 11));

    pg.text(45, y, "Année Scolaire " + academicYear); y += 34;
    pg.text(45, y, "Nom : " + lastName); y += 26;
    pg.text(45, y, "Prénoms : " + firstName); y += 26;
    pg.text(45, y, "Date et lieu de naissance : " + birthDate + (birthPlace.isEmpty() ? "" : (" à " + birthPlace))); y += 26;
    pg.text(45, y, "Nom du père : " + fatherName); y += 26;
    pg.text(45, y, "Nom de la mère : " + motherName); y += 26;
    pg.text(45, y, "Inscrit(e) sous le numéro matricule : " + matricule); y += 26;
    pg.text(45, y, "Date d'inscription : " + entryDate); y += 26;
    pg.text(45, y, "Actuellement en classe de : " + currentClass); y += 26;
    pg.text(45, y, "Dernière classe suivie : " + previousClass); y += 40;

    pg.text(45, y, "Le présent certificat est délivré pour servir et valoir ce que de droit"); y += 32;
    pg.text(80, y, "Usage :");
    drawCheckbox(pg, 140, y, "Pièce justificative");
    drawCheckbox(pg, 300, y, "Scolarité");
    y += 32;
    pg.text(45, y, "Validité : moins de trois mois"); y += 60;

    pg.text(360, y, "Tolagnaro, le " + today.toString("dd/MM/yyyy")); y += 60;
    pg.text(400, y, "Frère Directeur");

    drawFooter(pg);
    return true;
}

void render(QPrinter &printer, const std::function<void(Page &)> &draw)
{
    printer.setPageSize(QPageSize(QPageSize::A4));
    printer.setFullPage(true);   // l'origine (0,0) = coin du papier, la marge est gérée par la mise en page
    QPainter p(&printer);
    if (!p.isActive()) return;
    Page pg(printer, p);
    draw(pg);
    p.end();
}

}

PrintManager::PrintManager(QObject *parent) : QObject(parent) {}

bool PrintManager::printStudentList(const QString &className)
{
    QPrinter printer(QPrinter::HighResolution);
    QPrintDialog dlg(&printer);
    if (dlg.exec() != QDialog::Accepted) return false;
    render(printer, [&](Page &pg) { drawStudents(pg, className); });
    return true;
}

bool PrintManager::exportStudentsPdf(const QString &path, const QString &className)
{
    if (path.isEmpty()) return false;
    QPrinter printer(QPrinter::HighResolution);
    printer.setOutputFormat(QPrinter::PdfFormat);
    printer.setOutputFileName(path);
    render(printer, [&](Page &pg) { drawStudents(pg, className); });
    return true;
}

bool PrintManager::printTeacherList()
{
    QPrinter printer(QPrinter::HighResolution);
    QPrintDialog dlg(&printer);
    if (dlg.exec() != QDialog::Accepted) return false;
    render(printer, [&](Page &pg) { drawTeachers(pg); });
    return true;
}


bool drawStudentCard(Page &pg, int studentId)
{
    QSqlQuery q(QSqlDatabase::database());
    q.prepare("SELECT matricule,last_name,first_name,current_class,photo FROM students WHERE id=? AND deleted_at IS NULL");
    q.addBindValue(studentId);
    if (!q.exec() || !q.next()) return false;

    const QString matricule = q.value(0).toString();
    const QString lastName = q.value(1).toString();
    const QString firstName = q.value(2).toString();
    const QString currentClass = q.value(3).toString();
    const QString photoPath = q.value(4).toString();

    const QDate today = QDate::currentDate();
    const int startYear = today.month() >= 9 ? today.year() : today.year() - 1;
    const QString academicYear = QString("%1 – %2").arg(startYear).arg(startYear + 1);

    const double x = 45, y = 70, w = 340, h = 220;
    QPainter &p = pg.p;

    p.setPen(QPen(QColor("#D5DEE3"), 1));
    p.setBrush(Qt::white);
    p.drawRoundedRect(QRectF(pg.px(x), pg.px(y), pg.px(w), pg.px(h)), pg.px(12), pg.px(12));

    p.setPen(Qt::NoPen);
    p.setBrush(QColor("#0F9D8F"));
    p.drawRoundedRect(QRectF(pg.px(x), pg.px(y), pg.px(w), pg.px(56)), pg.px(12), pg.px(12));
    p.drawRect(QRectF(pg.px(x), pg.px(y + 40), pg.px(w), pg.px(16)));

    p.setPen(Qt::white);
    p.setFont(QFont("Arial", 12, QFont::Bold));
    pg.text(x + 16, y + 24, QStringLiteral("ESCATO GS"));
    p.setFont(QFont("Arial", 9));
    pg.text(x + 16, y + 42, QStringLiteral("CARTE ÉLÈVE  •  ") + academicYear);

    const double photoX = x + 16, photoY = y + 74, photoW = 92, photoH = 118;
    p.setPen(QPen(QColor("#D5DEE3"), 1));
    p.setBrush(QColor("#F1F5F7"));
    p.drawRect(QRectF(pg.px(photoX), pg.px(photoY), pg.px(photoW), pg.px(photoH)));
    if (!photoPath.isEmpty() && QFile::exists(photoPath)) {
        const QPixmap photo(photoPath);
        p.drawPixmap(QRect(pg.px(photoX), pg.px(photoY), pg.px(photoW), pg.px(photoH)),
                     photo.scaled(pg.px(photoW), pg.px(photoH), Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation));
    }

    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 13, QFont::Bold));
    pg.cell(x + 124, y + 96, 200, lastName.toUpper());
    p.setFont(QFont("Arial", 11));
    pg.cell(x + 124, y + 116, 200, firstName);
    p.setFont(QFont("Arial", 9));
    p.setPen(QColor("#667085"));
    pg.text(x + 124, y + 140, "Matricule");
    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 10, QFont::Bold));
    pg.cell(x + 124, y + 154, 200, matricule);
    p.setFont(QFont("Arial", 9));
    p.setPen(QColor("#667085"));
    pg.text(x + 124, y + 172, "Classe");
    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 10, QFont::Bold));
    pg.cell(x + 124, y + 186, 200, currentClass);

    const qrcodegen::QrCode qr = qrcodegen::QrCode::encodeText(matricule.toUtf8().constData(),
                                                               qrcodegen::QrCode::Ecc::MEDIUM);
    const int modules = qr.getSize();
    const int border = 2;
    const double qrSide = 60;
    const double cell = qrSide / (modules + 2 * border);
    const double qrX = x + w - qrSide - 16, qrY = y + h - qrSide - 16;
    p.setPen(Qt::NoPen);
    p.setBrush(Qt::white);
    p.drawRect(QRectF(pg.px(qrX - 2), pg.px(qrY - 2), pg.px(qrSide + 4), pg.px(qrSide + 4)));
    p.setBrush(QColor("#0B2A43"));
    for (int yy = 0; yy < modules; ++yy)
        for (int xx = 0; xx < modules; ++xx)
            if (qr.getModule(xx, yy))
                p.drawRect(QRectF(pg.px(qrX + (xx + border) * cell), pg.px(qrY + (yy + border) * cell),
                                  pg.px(cell) + 1, pg.px(cell) + 1));
    return true;
}


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

bool PrintManager::printStudentCertificate(int studentId)
{
    QPrinter printer(QPrinter::HighResolution);
    QPrintDialog dlg(&printer);
    if (dlg.exec() != QDialog::Accepted) return false;
    bool ok = false;
    render(printer, [&](Page &pg) { ok = drawCertificate(pg, studentId); });
    return ok;
}

bool PrintManager::exportStudentCertificatePdf(const QString &path, int studentId)
{
    if (path.isEmpty()) return false;
    QPrinter printer(QPrinter::HighResolution);
    printer.setOutputFormat(QPrinter::PdfFormat);
    printer.setOutputFileName(path);
    bool ok = false;
    render(printer, [&](Page &pg) { ok = drawCertificate(pg, studentId); });
    return ok;
}

bool PrintManager::printStudentCard(int studentId)
{
    QPrinter printer(QPrinter::HighResolution);
    QPrintDialog dlg(&printer);
    if (dlg.exec() != QDialog::Accepted) return false;
    bool ok = false;
    render(printer, [&](Page &pg) { ok = drawStudentCard(pg, studentId); });
    return ok;
}

bool PrintManager::exportStudentCardPdf(const QString &path, int studentId)
{
    if (path.isEmpty()) return false;
    QPrinter printer(QPrinter::HighResolution);
    printer.setOutputFormat(QPrinter::PdfFormat);
    printer.setOutputFileName(path);
    bool ok = false;
    render(printer, [&](Page &pg) { ok = drawStudentCard(pg, studentId); });
    return ok;
}

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
