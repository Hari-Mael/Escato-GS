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
