#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-importation-donnees main
git rm -q --ignore-unmatch install-phase*.sh || true

cat > qml/pages/ImportPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var result: ({})
    readonly property string template: school.studentsCsvTemplate()

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 18

            Label { text: "Importation des données"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: helpColumn.implicitHeight + 40
                ColumnLayout {
                    id: helpColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Importer des élèves"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Copiez vos élèves depuis un tableur (Excel, LibreOffice) et collez-les ci-dessous, en gardant la première ligne d'en-tête. Colonnes obligatoires : nom, prenom, date_naissance (AAAA-MM-JJ), classe, telephone_parent, adresse. Colonnes facultatives : lieu_naissance, email_parent."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Label { text: "Modèle d'en-tête :"; font.bold: true }
                    TextField {
                        Layout.fillWidth: true
                        readOnly: true
                        selectByMouse: true
                        text: root.template
                    }
                    Label { text: "Données à importer :"; font.bold: true }
                    TextArea {
                        id: csvInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180
                        placeholderText: root.template + "Rakoto;Jean;2014-03-04;Tolagnaro;CM2;0340000000;parent@mail.mg;Toamasina"
                        wrapMode: TextArea.NoWrap
                        selectByMouse: true
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppButton {
                            text: "Importer les élèves"; highlighted: true
                            onClicked: root.result = school.importStudentsCsv(csvInput.text)
                        }
                        AppButton { text: "Vider"; onClicked: { csvInput.text = ""; root.result = ({}) } }
                        Item { Layout.fillWidth: true }
                    }
                    Label {
                        visible: root.result.imported !== undefined
                        text: "Élèves importés : " + (root.result.imported || 0) + "   ·   Lignes refusées : " + (root.result.rejected || 0)
                        font.bold: true
                        color: (root.result.rejected || 0) === 0 ? "#0F9D8F" : "#B7791F"
                    }
                    Repeater {
                        model: root.result.errors || []
                        delegate: Label { text: modelData; color: "#C62828"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
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

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE bool addStudent(const QVariantMap &v);\n',
     '    Q_INVOKABLE bool addStudent(const QVariantMap &v);\n    Q_INVOKABLE QVariantMap importStudentsCsv(const QString &csv);\n    Q_INVOKABLE QString studentsCsvTemplate() const;\n')

cpp = 'src/core/SchoolApp.cpp'
s = open(cpp, encoding='utf-8').read()
s += '''
QString SchoolApp::studentsCsvTemplate() const
{
    return QStringLiteral("nom;prenom;date_naissance;lieu_naissance;classe;telephone_parent;email_parent;adresse\\n");
}

QVariantMap SchoolApp::importStudentsCsv(const QString &csv)
{
    QVariantMap out;
    QVariantList errors;
    int imported = 0;
    out["imported"] = 0;
    out["rejected"] = 0;
    if (!can("students.create")) {
        emit errorOccurred(QStringLiteral("Droit insuffisant pour importer des élèves."));
        out["errors"] = errors;
        return out;
    }
    QStringList lines;
    for (const QString &raw : csv.split('\\n')) {
        const QString line = raw.trimmed();
        if (!line.isEmpty()) lines << line;
    }
    if (lines.size() < 2) {
        errors << QStringLiteral("Il faut une ligne d'en-tête et au moins une ligne d'élève.");
        out["errors"] = errors;
        out["rejected"] = errors.size();
        return out;
    }
    const QChar delim = lines.first().contains(';') ? QChar(';') : QChar(',');
    auto clean = [](QString f) { f = f.trimmed(); if (f.startsWith('"') && f.endsWith('"') && f.size() >= 2) f = f.mid(1, f.size() - 2); return f.trimmed(); };
    auto normKey = [](QString k) { k = k.trimmed().toLower(); k.remove('_'); k.remove(' '); k.remove('-'); return k; };

    QVariantMap alias;
    alias["nom"] = "lastName"; alias["lastname"] = "lastName";
    alias["prenom"] = "firstName"; alias["prénom"] = "firstName"; alias["firstname"] = "firstName";
    alias["datenaissance"] = "birthDate"; alias["birthdate"] = "birthDate";
    alias["lieunaissance"] = "birthPlace"; alias["birthplace"] = "birthPlace";
    alias["classe"] = "className"; alias["classname"] = "className";
    alias["telephoneparent"] = "parentPhone"; alias["parentphone"] = "parentPhone";
    alias["emailparent"] = "parentEmail"; alias["parentemail"] = "parentEmail";
    alias["adresse"] = "address"; alias["address"] = "address";

    QStringList header;
    for (const QString &h : lines.first().split(delim)) header << normKey(clean(h));
    QVariantList columns;
    for (const QString &h : header) columns << alias.value(h, QString()).toString();
    const QStringList required = {"lastName", "firstName", "birthDate", "className", "parentPhone", "address"};
    QStringList missing;
    for (const QString &r : required) if (!columns.contains(r)) missing << r;
    if (!missing.isEmpty()) {
        errors << QStringLiteral("Colonnes manquantes dans l'en-tête : ") + missing.join(", ");
        out["errors"] = errors;
        out["rejected"] = errors.size();
        return out;
    }

    const QStringList classList = classes();
    for (int i = 1; i < lines.size(); ++i) {
        const QStringList fields = lines.at(i).split(delim);
        QVariantMap row;
        for (int c = 0; c < columns.size() && c < fields.size(); ++c) {
            const QString key = columns.at(c).toString();
            if (!key.isEmpty()) row[key] = clean(fields.at(c));
        }
        const QString where = QStringLiteral("Ligne %1 : ").arg(i + 1);
        bool ok = true;
        for (const QString &r : required) {
            if (row.value(r).toString().isEmpty()) { errors << where + QStringLiteral("champ « %1 » vide").arg(r); ok = false; break; }
        }
        if (!ok) continue;
        if (!classList.contains(row.value("className").toString())) {
            errors << where + QStringLiteral("classe inconnue « %1 »").arg(row.value("className").toString());
            continue;
        }
        if (!QDate::fromString(row.value("birthDate").toString(), "yyyy-MM-dd").isValid()) {
            errors << where + QStringLiteral("date de naissance invalide (AAAA-MM-JJ attendu)");
            continue;
        }
        QSqlQuery dup(m_db.db());
        dup.prepare("SELECT COUNT(*) FROM students WHERE last_name=? AND first_name=? AND birth_date=? AND deleted_at IS NULL");
        dup.addBindValue(row.value("lastName").toString());
        dup.addBindValue(row.value("firstName").toString());
        dup.addBindValue(row.value("birthDate").toString());
        if (dup.exec() && dup.next() && dup.value(0).toInt() > 0) {
            errors << where + QStringLiteral("élève déjà présent (même nom, prénom et date de naissance)");
            continue;
        }
        if (addStudent(row)) ++imported;
        else errors << where + QStringLiteral("enregistrement refusé");
    }
    audit("import", "students", imported, QStringLiteral("%1 élèves importés").arg(imported));
    if (imported > 0) emit dataChanged();
    out["imported"] = imported;
    out["rejected"] = errors.size();
    out["errors"] = errors;
    return out;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sb = 'qml/components/Sidebar.qml'
edit(sb, '                ["finextra", "Bourses, affectations et états", "📑"],\n',
     '                ["finextra", "Bourses, affectations et états", "📑"],\n                ["import", "Importation des données", "📥"],\n')
mq = 'qml/Main.qml'
edit(mq, '"finextra":24}', '"finextra":24,"import":25}')
edit(mq, '                        FinanceExtraPage {}\n', '                        FinanceExtraPage {}\n                        ImportPage {}\n')
cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/FinanceExtraPage.qml\n', '        qml/pages/FinanceExtraPage.qml\n        qml/pages/ImportPage.qml\n')
print("phase 15 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: importation des élèves depuis un tableau (validation ligne par ligne, rapport des refus)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-importation-donnees."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-importation-donnees"
