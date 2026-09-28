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
    p.setFont(QFont("Arial", 15, QFont::Bold));
    pg.text(left + 95, top + 24, "École Sacre Coeur");

    p.setFont(QFont("Arial", 10));
    pg.text(left + 95, top + 45, "BP 85 Tolagnaro");
    pg.text(left + 95, top + 63, "034 52 812 71");

    p.setPen(QPen(QColor("#B7B7B7"), 1));
    p.drawLine(pg.px(left), pg.px(top + 94), pg.px(right), pg.px(top + 94));

    p.setPen(Qt::black);
    p.setFont(QFont("Arial", 16, QFont::Bold));
    pg.text(left, top + 122, documentTitle);

    return top + 155;
}

void drawFooter(Page &pg)
{
    pg.p.setPen(QPen(QColor("#B7B7B7"), 1));
    pg.p.drawLine(pg.px(45), pg.px(805), pg.px(555), pg.px(805));
    pg.p.setPen(QColor("#555555"));
    pg.p.setFont(QFont("Arial", 8));
    pg.text(45, 823, "ESCATO — École Sacre Coeur — Document administratif");
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
