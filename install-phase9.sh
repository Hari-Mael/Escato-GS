#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-famille-bulletin-filtres main
git rm -q --ignore-unmatch install-phase4.sh install-phase5.sh install-phase6.sh install-phase7.sh install-phase8.sh install-phase9.sh || true

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
    property var oneTimeFees: []
    property var bulletin: ({})
    property var bulletinSubjects: []

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function mention(avg) {
        var v = Number(avg)
        if (v >= 16) return "Très bien"
        if (v >= 14) return "Bien"
        if (v >= 12) return "Assez bien"
        if (v >= 10) return "Passable"
        return "Insuffisant"
    }
    function reload() {
        students = school.myStudents()
        if (selectedId === 0 && students.length > 0) selectedId = students[0].id
        refresh()
    }
    function refreshBulletin() {
        if (selectedId <= 0) { bulletin = ({}); bulletinSubjects = []; return }
        bulletin = school.familyBulletin(selectedId, termBox.currentText)
        bulletinSubjects = bulletin.subjects || []
    }
    function refresh() {
        if (selectedId <= 0) {
            detail = ({}); invoices = []; payments = []; oneTimeFees = []
            bulletin = ({}); bulletinSubjects = []
            return
        }
        detail = school.familyStudent(selectedId)
        invoices = school.familyInvoices(selectedId)
        payments = school.familyPayments(selectedId)
        oneTimeFees = school.studentOneTimeFees(selectedId)
        refreshBulletin()
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
                clip: true

                ScrollView {
                    id: scroll
                    anchors.fill: parent
                    anchors.margins: 22
                    clip: true

                    ColumnLayout {
                        width: scroll.availableWidth
                        spacing: 12

                        Label {
                            text: (detail.firstName || "") + " " + (detail.lastName || "")
                            font.pixelSize: 24; font.bold: true; color: "#0B2A43"
                        }
                        Label {
                            text: "Classe : " + (detail.className || "") + "   •   Matricule : " + (detail.matricule || "")
                            color: "#667085"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            radius: 12
                            color: "#F4F7FA"
                            implicitHeight: bulletinColumn.implicitHeight + 32

                            ColumnLayout {
                                id: bulletinColumn
                                x: 16; y: 16
                                width: parent.width - 32
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: "Bulletin"; font.pixelSize: 18; font.bold: true; color: "#0B2A43"; Layout.fillWidth: true }
                                    ComboBox {
                                        id: termBox
                                        Layout.preferredWidth: 170
                                        model: school.terms()
                                        onCurrentTextChanged: root.refreshBulletin()
                                    }
                                    AppButton {
                                        text: "🖨 Imprimer"
                                        onClicked: printer.printBulletin(selectedId, termBox.currentText)
                                    }
                                }
                                Label {
                                    visible: bulletinSubjects.length === 0
                                    text: "Aucune note enregistrée pour ce trimestre."
                                    color: "#667085"
                                }
                                RowLayout {
                                    visible: bulletinSubjects.length > 0
                                    Layout.fillWidth: true
                                    Label { text: "Matière"; font.bold: true; color: "#667085"; Layout.fillWidth: true }
                                    Label { text: "Moyenne /20"; font.bold: true; color: "#667085"; Layout.preferredWidth: 110 }
                                    Label { text: "Appréciation"; font.bold: true; color: "#667085"; Layout.preferredWidth: 130 }
                                }
                                Repeater {
                                    model: bulletinSubjects
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: modelData.subject; Layout.fillWidth: true; elide: Text.ElideRight }
                                        Label { text: Number(modelData.average).toFixed(2); Layout.preferredWidth: 110 }
                                        Label { text: root.mention(modelData.average); color: "#667085"; Layout.preferredWidth: 130 }
                                    }
                                }
                                Label {
                                    visible: bulletinSubjects.length > 0
                                    text: "Moyenne générale : " + (bulletin.generalAverage || "—") + " / 20   •   " + (bulletin.generalAverage ? root.mention(bulletin.generalAverage) : "")
                                    font.pixelSize: 16; font.bold: true; color: "#0B2A43"
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Factures et échéances"; font.pixelSize: 18; font.bold: true; color: "#0B2A43"; Layout.fillWidth: true }
                            AppButton { text: "🖨 Demande de paiement"; onClicked: printer.printPaymentRequest(selectedId) }
                        }
                        Repeater {
                            model: invoices
                            delegate: RowLayout {
                                Layout.fillWidth: true
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

                        Label { text: "Frais ponctuels"; font.pixelSize: 18; font.bold: true; color: "#0B2A43" }
                        Label {
                            visible: oneTimeFees.length === 0
                            text: "Aucun frais ponctuel assigné."
                            color: "#667085"
                        }
                        Repeater {
                            model: oneTimeFees
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                Label { text: modelData.name; Layout.fillWidth: true }
                                Label { text: "échéance " + modelData.dueDate; color: "#667085" }
                                Label { text: fmt(modelData.amount); font.bold: true }
                                Label {
                                    text: modelData.status === "paid" ? "Payé" : "À payer"
                                    color: modelData.status === "paid" ? "#0F9D8F" : "#C62828"
                                    Layout.preferredWidth: 90
                                }
                                AppButton {
                                    visible: modelData.status === "paid"
                                    text: "🧾 Reçu"
                                    onClicked: printer.printReceipt(modelData.paymentId)
                                }
                            }
                        }

                        Label { text: "Paiements et reçus"; font.pixelSize: 18; font.bold: true; color: "#0B2A43" }
                        Repeater {
                            model: payments
                            delegate: RowLayout {
                                Layout.fillWidth: true
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
}
QML

cat > qml/pages/AccountsPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var rows: []
    property var shown: []

    function applyFilters() {
        var q = searchUsers.text.trim().toLowerCase()
        var role = roleFilter.currentIndex === 0 ? "" : roleFilter.currentText
        var st = statusFilter.currentIndex
        shown = rows.filter(function(u) {
            if (role !== "" && u.role !== role) return false
            if (st === 1 && u.status !== "active") return false
            if (st === 2 && u.status === "active") return false
            if (q !== "" && (u.name + " " + u.email).toLowerCase().indexOf(q) < 0) return false
            return true
        })
    }
    function refresh() {
        rows = school.users()
        applyFilters()
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 15

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Comptes & sécurité"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            AppButton { text: "Créer un compte"; onClicked: create.open() }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            AppTextField {
                id: searchUsers
                placeholderText: "Rechercher nom ou e-mail"
                Layout.fillWidth: true
                onTextChanged: root.applyFilters()
            }
            ComboBox {
                id: roleFilter
                Layout.preferredWidth: 180
                model: ["Tous les rôles"].concat(school.roles())
                onCurrentIndexChanged: root.applyFilters()
            }
            ComboBox {
                id: statusFilter
                Layout.preferredWidth: 160
                model: ["Tous les statuts", "Actifs", "Bloqués"]
                onCurrentIndexChanged: root.applyFilters()
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.shown
            delegate: Rectangle {
                width: parent.width
                height: 65
                color: index % 2 ? "#FAFBFC" : "white"
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 25
                    Label { text: modelData.name; width: 180; elide: Text.ElideRight }
                    Label { text: modelData.email; width: 220; elide: Text.ElideRight }
                    Label { text: modelData.role; width: 130 }
                    Label { text: modelData.status; width: 100 }
                    Label { text: modelData.blockedReason; width: 250; elide: Text.ElideRight }
                    AppButton {
                        text: "Bloquer"
                        enabled: modelData.status === "active"
                        onClicked: school.blockUser(modelData.id, "administratif", "Blocage administratif")
                    }
                    AppButton {
                        text: "Débloquer"
                        enabled: modelData.status !== "active"
                        onClicked: school.unblockUser(modelData.id)
                    }
                }
            }
        }
    }

    Dialog {
        id: create
        title: "Créer un compte"
        modal: true
        anchors.centerIn: Overlay.overlay
        standardButtons: Dialog.Ok | Dialog.Cancel
        Column {
            spacing: 8
            width: 400
            AppTextField { id: name; placeholderText: "Nom" }
            AppTextField { id: email; placeholderText: "E-mail" }
            AppTextField { id: password; placeholderText: "Mot de passe"; echoMode: TextInput.Password }
            ComboBox { id: role; model: school.roles() }
        }
        onAccepted: school.createUser({name: name.text, email: email.text, password: password.text, role: role.currentText})
    }
}
QML

python3 <<'PY'
def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

pm = 'src/core/PrintManager.cpp'
helpers = '''
QString appreciationFor(double avg)
{
    if (avg >= 16) return QStringLiteral("Très bien");
    if (avg >= 14) return QStringLiteral("Bien");
    if (avg >= 12) return QStringLiteral("Assez bien");
    if (avg >= 10) return QStringLiteral("Passable");
    return QStringLiteral("Insuffisant");
}

bool drawBulletin(Page &pg, int studentId, const QString &term)
{
    QSqlQuery s(QSqlDatabase::database());
    s.prepare("SELECT matricule,last_name,first_name,current_class FROM students WHERE id=? AND deleted_at IS NULL");
    s.addBindValue(studentId);
    if (!s.exec() || !s.next()) return false;

    QSqlQuery g(QSqlDatabase::database());
    g.prepare("SELECT c.subject,ROUND(AVG((g.score*20.0)/e.max_score),2) FROM grades g JOIN exams e ON e.id=g.exam_id "
              "JOIN courses c ON c.id=e.course_id WHERE g.student_id=? AND e.term=? GROUP BY c.subject ORDER BY c.subject");
    g.addBindValue(studentId);
    g.addBindValue(term);
    if (!g.exec()) return false;

    double y = drawOfficialHeader(pg, QStringLiteral("BULLETIN DE NOTES - ") + term.toUpper());
    QPainter &p = pg.p;
    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 11));
    pg.text(45, y, QStringLiteral("Élève : ") + s.value(1).toString().toUpper() + " " + s.value(2).toString()); y += 22;
    pg.text(45, y, QStringLiteral("Matricule : ") + s.value(0).toString()
            + QStringLiteral("     Classe : ") + s.value(3).toString()); y += 34;

    p.setFont(QFont("Arial", 10, QFont::Bold));
    pg.text(45, y, QStringLiteral("Matière"));
    pg.text(340, y, QStringLiteral("Moyenne /20"));
    pg.text(430, y, QStringLiteral("Appréciation"));
    y += 8;
    p.setPen(QPen(QColor("#D5DEE3"), 0.8));
    p.drawLine(QPoint(pg.px(45), pg.px(y)), QPoint(pg.px(550), pg.px(y)));
    y += 18;

    double sum = 0;
    int count = 0;
    p.setPen(QColor("#0B2A43"));
    p.setFont(QFont("Arial", 10));
    while (g.next()) {
        const double avg = g.value(1).toDouble();
        sum += avg;
        ++count;
        pg.cell(45, y, 280, g.value(0).toString());
        pg.cell(340, y, 80, QString::number(avg, 'f', 2));
        pg.cell(430, y, 120, appreciationFor(avg));
        y += 20;
    }
    if (count == 0) {
        pg.text(45, y, QStringLiteral("Aucune note enregistrée pour ce trimestre."));
        y += 20;
    }

    y += 14;
    p.setFont(QFont("Arial", 13, QFont::Bold));
    const double general = count ? sum / count : 0;
    pg.text(45, y, QStringLiteral("Moyenne générale : ")
            + (count ? QString::number(general, 'f', 2) : QStringLiteral("—")) + QStringLiteral(" / 20"));
    y += 24;
    p.setFont(QFont("Arial", 11));
    pg.text(45, y, QStringLiteral("Appréciation générale : ") + (count ? appreciationFor(general) : QStringLiteral("—")));

    const double sigY = y + 90;
    p.setFont(QFont("Arial", 10, QFont::Bold));
    pg.text(370, sigY, settingText("signatory_title", "Le Frère Directeur"));
    p.setPen(QPen(QColor("#667085"), 0.8));
    p.drawLine(QPoint(pg.px(360), pg.px(sigY + 60)), QPoint(pg.px(550), pg.px(sigY + 60)));
    return true;
}
'''
anchor = 'bool PrintManager::printStudentCertificate(int studentId)\n'
edit(pm, anchor, helpers + '\n' + anchor)

s = open(pm, encoding='utf-8').read()
s += '''
bool PrintManager::printBulletin(int studentId, const QString &term)
{
    QPrinter printer(QPrinter::HighResolution);
    QPrintDialog dlg(&printer);
    if (dlg.exec() != QDialog::Accepted) return false;
    bool ok = false;
    render(printer, [&](Page &pg) { ok = drawBulletin(pg, studentId, term); });
    return ok;
}

bool PrintManager::exportBulletinPdf(const QString &path, int studentId, const QString &term)
{
    if (path.isEmpty()) return false;
    QPrinter printer(QPrinter::HighResolution);
    printer.setOutputFormat(QPrinter::PdfFormat);
    printer.setOutputFileName(path);
    bool ok = false;
    render(printer, [&](Page &pg) { ok = drawBulletin(pg, studentId, term); });
    return ok;
}
'''
open(pm, 'w', encoding='utf-8').write(s)

ph = 'src/core/PrintManager.h'
edit(ph, '    Q_INVOKABLE bool exportAttestationPdf(const QString &path, int studentId, const QString &kind);\n',
     '    Q_INVOKABLE bool exportAttestationPdf(const QString &path, int studentId, const QString &kind);\n'
     '    Q_INVOKABLE bool printBulletin(int studentId, const QString &term);\n'
     '    Q_INVOKABLE bool exportBulletinPdf(const QString &path, int studentId, const QString &term);\n')
print("phase 9 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: bulletin complet dans l'espace famille (choix du trimestre, impression), frais ponctuels visibles, filtres sur les comptes"

echo ""
echo "Commit créé sur la branche feat/escato-gs-famille-bulletin-filtres."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-famille-bulletin-filtres"
