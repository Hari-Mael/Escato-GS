#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-cartes-teal main

mkdir -p src/third_party/qrcodegen
RAW=https://raw.githubusercontent.com/nayuki/QR-Code-generator/master/cpp
curl -fsSL "$RAW/qrcodegen.hpp" -o src/third_party/qrcodegen/qrcodegen.hpp
curl -fsSL "$RAW/qrcodegen.cpp" -o src/third_party/qrcodegen/qrcodegen.cpp

cat > qml/components/AppButton.qml <<'QML'
import QtQuick
import QtQuick.Controls

Button {
    id: control

    readonly property color accent: "#0F9D8F"
    readonly property color accentDark: "#0B7F74"
    readonly property color accentLight: "#E6F6F4"

    hoverEnabled: true
    padding: 10
    leftPadding: 18
    rightPadding: 18
    font.pixelSize: 14
    font.weight: Font.DemiBold

    contentItem: Text {
        text: control.text
        font: control.font
        color: !control.enabled ? "#7A8790" : control.highlighted ? "white" : accentDark
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 10
        color: {
            if (!control.enabled) return "#D5DEE3"
            if (control.highlighted) return control.down ? control.accentDark : (control.hovered ? "#12B0A0" : control.accent)
            return control.down ? "#D2EFEB" : (control.hovered ? "#D8F2EE" : control.accentLight)
        }
        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
QML

cat > qml/components/AppTextField.qml <<'QML'
import QtQuick
import QtQuick.Controls

TextField {
    id: field

    color: "#1F2937"
    placeholderTextColor: "#8A97A6"
    selectionColor: "#0F9D8F"
    selectedTextColor: "white"
    font.pixelSize: 14
    leftPadding: 12
    rightPadding: 12
    topPadding: 10
    bottomPadding: 10

    background: Rectangle {
        radius: 10
        color: field.activeFocus ? "#E6F6F4" : "#F1F5F7"
        border.width: 0
    }
}
QML

cat > qml/pages/StudentDetailPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    property int studentId: 0
    signal back()

    ColumnLayout {
        anchors.fill: parent; spacing:16
        RowLayout {
            Label{text:"Fiche élève";font.pixelSize:28;font.bold:true}
            Item{Layout.fillWidth:true}
            Button{text:"← Retour";onClicked:back()}
            Button{text:"🖨 Imprimer la liste";onClicked:printer.printStudentList(info.className)}
            Button{text:"🪪 Carte élève";onClicked:printer.printStudentCard(studentId)}
            Button{text:"🖨 Certificat de scolarité";onClicked:printer.printStudentCertificate(studentId)}
        }
        Rectangle {
            Layout.fillWidth:true; Layout.fillHeight:true; radius:16; color:"white"
            Column {
                anchors.fill:parent; anchors.margins:25; spacing:12
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
                    spacing:8
                    Button{text:"Diplômé";onClicked:school.graduateStudent(studentId)}
                    Button{text:"Bloquer";onClicked:school.blockStudent(studentId,"Blocage administratif")}
                    Button{text:"Débloquer";onClicked:school.unblockStudent(studentId)}
                }
            }
        }
        Rectangle {
            Layout.fillWidth:true; Layout.preferredHeight:300; radius:16; color:"white"
            ColumnLayout {
                anchors.fill:parent; anchors.margins:20; spacing:10
                Label{text:"Parents et tuteurs";font.pixelSize:20;font.bold:true;color:"#0B2A43"}
                ListView {
                    Layout.fillWidth:true; Layout.fillHeight:true; clip:true
                    model: guardianRows
                    delegate: RowLayout {
                        width: ListView.view.width
                        Label {
                            text: (modelData.isPrimary ? "★ " : "") + modelData.fullName + " — " + modelData.relation
                            Layout.fillWidth:true; elide: Text.ElideRight
                        }
                        Label{text:modelData.phone; color:"#667085"}
                        Button{text:"Retirer"; onClicked: school.removeGuardian(modelData.linkId)}
                    }
                }
                RowLayout {
                    Layout.fillWidth:true; spacing:8
                    TextField{id:gName; placeholderText:"Nom complet"; Layout.fillWidth:true}
                    TextField{id:gRelation; placeholderText:"Lien (père, mère…)"; Layout.preferredWidth:160}
                    TextField{id:gPhone; placeholderText:"Téléphone"; Layout.preferredWidth:140}
                    CheckBox{id:gPrimary; text:"Principal"}
                    Button{
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
    }
    property var info: ({})
    property var guardianRows: []
    onStudentIdChanged: refresh()
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }
    function refresh() {
        info = school.student(studentId)
        guardianRows = school.guardians(studentId)
    }
}
QML

python3 <<'PY'
import glob, re

def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:60])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS guardians(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            full_name TEXT NOT NULL,
            phone TEXT NOT NULL,
            email TEXT,
            relation TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS student_guardians(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            guardian_id INTEGER NOT NULL REFERENCES guardians(id) ON DELETE CASCADE,
            is_primary INTEGER NOT NULL DEFAULT 0,
            UNIQUE(student_id, guardian_id)
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QStringList terms() const;\n', '''    Q_INVOKABLE QStringList terms() const;

    Q_INVOKABLE QVariantList guardians(int studentId) const;
    Q_INVOKABLE bool addGuardian(int studentId, const QVariantMap &v);
    Q_INVOKABLE bool removeGuardian(int linkId);
''')

cpp = 'src/core/SchoolApp.cpp'
s = open(cpp, encoding='utf-8').read()
start = s.index('QStringList SchoolApp::classes() const {')
end = s.index('QStringList SchoolApp::roles() const')
s = s[:start] + '''QStringList SchoolApp::classes() const
{
    return {"CP1","CP2","CE1","CE2","CM1","CM2",
            "6ème 1","6ème 2","6ème 3","5ème 1","5ème 2","5ème 3",
            "4ème 1","4ème 2","4ème 3","3ème 1","3ème 2","3ème 3",
            "2nde 1","2nde 2","2nde 3","2nde 4",
            "1ère L1","1ère L2","1ère S1","1ère S2",
            "Terminale L1","Terminale L2","Terminale S"};
}
''' + s[end:]
s += '''
QVariantList SchoolApp::guardians(int studentId) const
{
    QVariantList out;
    if (!allowed({"administrateur", "enseignant"})) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT sg.id,g.id,g.full_name,g.phone,g.email,g.relation,sg.is_primary "
              "FROM student_guardians sg JOIN guardians g ON g.id=sg.guardian_id "
              "WHERE sg.student_id=? ORDER BY sg.is_primary DESC, g.full_name");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["linkId"] = q.value(0).toInt();
        m["guardianId"] = q.value(1).toInt();
        m["fullName"] = q.value(2).toString();
        m["phone"] = q.value(3).toString();
        m["email"] = q.value(4).toString();
        m["relation"] = q.value(5).toString();
        m["isPrimary"] = q.value(6).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addGuardian(int studentId, const QVariantMap &v)
{
    if (!allowed({"administrateur", "enseignant"})) return false;
    const QString fullName = v.value("fullName").toString().trimmed();
    const QString phone = v.value("phone").toString().trimmed();
    const QString relation = v.value("relation").toString().trimmed();
    if (fullName.isEmpty() || phone.isEmpty() || relation.isEmpty()) {
        emit errorOccurred(QStringLiteral("Nom, téléphone et lien de parenté sont obligatoires."));
        return false;
    }
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    QSqlQuery g(db);
    g.prepare("INSERT INTO guardians(full_name,phone,email,relation) VALUES(?,?,?,?)");
    g.addBindValue(fullName); g.addBindValue(phone);
    g.addBindValue(v.value("email").toString().trimmed()); g.addBindValue(relation);
    if (!g.exec()) { db.rollback(); emit errorOccurred(g.lastError().text()); return false; }
    const int guardianId = g.lastInsertId().toInt();
    QSqlQuery l(db);
    l.prepare("INSERT INTO student_guardians(student_id,guardian_id,is_primary) VALUES(?,?,?)");
    l.addBindValue(studentId); l.addBindValue(guardianId); l.addBindValue(v.value("isPrimary").toBool() ? 1 : 0);
    if (!l.exec()) { db.rollback(); emit errorOccurred(l.lastError().text()); return false; }
    db.commit();
    audit("create", "guardian", guardianId, QStringLiteral("élève %1").arg(studentId));
    emit dataChanged();
    return true;
}

bool SchoolApp::removeGuardian(int linkId)
{
    if (!allowed({"administrateur"})) return false;
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    QSqlQuery d(db);
    d.prepare("DELETE FROM student_guardians WHERE id=?");
    d.addBindValue(linkId);
    if (!d.exec()) { db.rollback(); return false; }
    QSqlQuery c(db);
    c.exec("DELETE FROM guardians WHERE id NOT IN (SELECT guardian_id FROM student_guardians)");
    db.commit();
    audit("delete", "guardian_link", linkId);
    emit dataChanged();
    return true;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

ph = 'src/core/PrintManager.h'
edit(ph, '    Q_INVOKABLE bool exportStudentCertificatePdf(const QString &path, int studentId);\n',
     '    Q_INVOKABLE bool exportStudentCertificatePdf(const QString &path, int studentId);\n'
     '    Q_INVOKABLE bool printStudentCard(int studentId);\n'
     '    Q_INVOKABLE bool exportStudentCardPdf(const QString &path, int studentId);\n')

pc = 'src/core/PrintManager.cpp'
edit(pc, '#include <functional>\n', '''#include <functional>
#include <QFile>
#include <QColor>
#include <QFont>
#include <QRectF>
#include "third_party/qrcodegen/qrcodegen.hpp"
''')

card = '''
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
'''
anchor = 'bool PrintManager::printStudentCertificate(int studentId)\n'
edit(pc, anchor, card + '\n' + anchor)
s = open(pc, encoding='utf-8').read()
s += '''
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
'''
open(pc, 'w', encoding='utf-8').write(s)

cm = 'CMakeLists.txt'
c = open(cm, encoding='utf-8').read()
c = c.replace('find_package(Qt6 REQUIRED COMPONENTS Quick Sql PrintSupport Widgets Network)',
              'find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Sql PrintSupport Widgets Network)')
c = c.replace('PRIVATE Qt6::Quick Qt6::Sql', 'PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Sql')
c = c.replace('    src/core/PrintManager.h\n)', '    src/core/PrintManager.h\n    src/third_party/qrcodegen/qrcodegen.cpp\n    src/third_party/qrcodegen/qrcodegen.hpp\n)')
c = c.replace('        qml/components/Toast.qml\n', '        qml/components/Toast.qml\n        qml/components/AppButton.qml\n        qml/components/AppTextField.qml\n')
assert 'QuickControls2' in c and 'qrcodegen.cpp' in c and 'AppButton.qml' in c
open(cm, 'w', encoding='utf-8').write(c)

mc = 'src/main.cpp'
m = open(mc, encoding='utf-8').read()
m = m.replace('#include <QQmlApplicationEngine>\n', '#include <QQmlApplicationEngine>\n#include <QQuickStyle>\n', 1)
m = m.replace('    QApplication app(argc, argv);\n', '    QApplication app(argc, argv);\n    QQuickStyle::setStyle(QStringLiteral("Basic"));\n', 1)
assert 'QQuickStyle::setStyle' in m
open(mc, 'w', encoding='utf-8').write(m)

for f in glob.glob('qml/**/*.qml', recursive=True):
    if f.endswith(('AppButton.qml', 'AppTextField.qml')):
        continue
    s = open(f, encoding='utf-8').read()
    o = s
    s = re.sub(r'\bButton(\s*\{)', r'AppButton\1', s)
    s = re.sub(r'\bTextField(\s*\{)', r'AppTextField\1', s)
    if s != o:
        if f.startswith('qml/pages/') and 'import "../components"' not in s:
            lines = s.split('\n')
            last = max(i for i, l in enumerate(lines) if l.startswith('import '))
            lines.insert(last + 1, 'import "../components"')
            s = '\n'.join(lines)
        open(f, 'w', encoding='utf-8').write(s)

edit('qml/components/Sidebar.qml', 'text: "ESCATO"', 'text: "ESCATO GS"')
edit('qml/pages/SetupPage.qml', 'text: "ESCATO"', 'text: "ESCATO GS"')
print("transformations appliquées")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: ESCATO GS - tuteurs des élèves, carte élève avec QR code, classes CP1 à Terminale, thème teal"

echo ""
echo "Commit créé sur la branche feat/escato-gs-cartes-teal."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-cartes-teal"
