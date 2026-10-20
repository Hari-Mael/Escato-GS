#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -f qml/pages/StudentFormPage.qml ] || [ ! -f qml/pages/ImportPage.qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-dates-logo-import main
git rm -q --ignore-unmatch install-*.sh || true

python3 <<'PY'
import re, glob

def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

cpp = 'src/core/SchoolApp.cpp'
s = open(cpp, encoding='utf-8').read()
helper = '''static QDate parseAnyDate(const QString &text)
{
    const QString t = text.trimmed();
    static const QStringList formats = {QStringLiteral("yyyy-MM-dd"), QStringLiteral("dd-MM-yyyy"),
                                        QStringLiteral("dd/MM/yyyy"), QStringLiteral("dd.MM.yyyy")};
    for (const QString &f : formats) {
        const QDate d = QDate::fromString(t, f);
        if (d.isValid()) return d;
    }
    return QDate();
}

'''
anchor = 'SchoolApp::SchoolApp(QObject *parent) : QObject(parent)\n'
assert s.count(anchor) == 1
s = s.replace(anchor, helper + anchor)
pattern = re.compile(r'QDate::fromString\(((?:[^,()]|\([^()]*\))+), "yyyy-MM-dd"\)')
s, n = pattern.subn(lambda m: 'parseAnyDate(' + m.group(1) + ')', s)
print("dates d'entrée rendues tolérantes :", n)
dup = '        QSqlQuery dup(m_db.db());\n'
assert s.count(dup) == 1
s = s.replace(dup, '        row["birthDate"] = parseAnyDate(row.value("birthDate").toString()).toString("yyyy-MM-dd");\n' + dup)
s += '''
QVariantMap SchoolApp::importTeachersCsv(const QString &csv)
{
    QVariantMap out;
    QVariantList errors;
    int imported = 0;
    if (!can("teachers.manage")) {
        emit errorOccurred(QStringLiteral("Droit insuffisant pour importer des enseignants."));
        out["imported"] = 0; out["rejected"] = 0; out["errors"] = errors;
        return out;
    }
    QStringList lines;
    for (const QString &raw : csv.split('\\n')) {
        const QString line = raw.trimmed();
        if (!line.isEmpty()) lines << line;
    }
    if (lines.size() < 2) {
        errors << QStringLiteral("Il faut une ligne d'en-tête et au moins une ligne d'enseignant.");
        out["imported"] = 0; out["rejected"] = errors.size(); out["errors"] = errors;
        return out;
    }
    const QChar delim = lines.first().contains(';') ? QChar(';') : QChar(',');
    auto clean = [](QString f) { f = f.trimmed(); if (f.startsWith('"') && f.endsWith('"') && f.size() >= 2) f = f.mid(1, f.size() - 2); return f.trimmed(); };
    auto normKey = [](QString k) { k = k.trimmed().toLower(); k.remove('_'); k.remove(' '); k.remove('-'); return k; };
    QVariantMap alias;
    alias["nom"] = "name"; alias["name"] = "name";
    alias["email"] = "email"; alias["courriel"] = "email";
    alias["matiere"] = "subject"; alias["subject"] = "subject";
    alias["contact"] = "contact"; alias["telephone"] = "contact";
    alias["cin"] = "cin";
    alias["motdepasse"] = "password"; alias["password"] = "password";
    QVariantList columns;
    for (const QString &h : lines.first().split(delim)) columns << alias.value(normKey(clean(h)), QString()).toString();
    QStringList missing;
    for (const QString &r : QStringList{"name", "email", "password"}) if (!columns.contains(r)) missing << r;
    if (!missing.isEmpty()) {
        errors << QStringLiteral("Colonnes manquantes dans l'en-tête : ") + missing.join(", ");
        out["imported"] = 0; out["rejected"] = errors.size(); out["errors"] = errors;
        return out;
    }
    for (int i = 1; i < lines.size(); ++i) {
        const QStringList fields = lines.at(i).split(delim);
        QVariantMap row;
        for (int c = 0; c < columns.size() && c < fields.size(); ++c) {
            const QString key = columns.at(c).toString();
            if (!key.isEmpty()) row[key] = clean(fields.at(c));
        }
        const QString where = QStringLiteral("Ligne %1 : ").arg(i + 1);
        if (row.value("name").toString().isEmpty() || row.value("email").toString().isEmpty() || row.value("password").toString().isEmpty()) {
            errors << where + QStringLiteral("nom, e-mail et mot de passe obligatoires");
            continue;
        }
        if (addTeacher(row)) ++imported;
        else errors << where + QStringLiteral("enregistrement refusé (e-mail déjà utilisé ou mot de passe trop court)");
    }
    audit("import", "teachers", imported, QStringLiteral("%1 enseignants importés").arg(imported));
    if (imported > 0) emit dataChanged();
    out["imported"] = imported;
    out["rejected"] = errors.size();
    out["errors"] = errors;
    return out;
}

QString SchoolApp::readTextFile(const QString &fileUrl) const
{
    if (!(can("students.create") || can("teachers.manage"))) return QString();
    const QUrl url(fileUrl);
    const QString local = url.isLocalFile() ? url.toLocalFile() : fileUrl;
    QFile f(local);
    if (!f.open(QIODevice::ReadOnly)) return QString();
    const QByteArray data = f.readAll();
    QString text = QString::fromUtf8(data);
    if (text.contains(QChar::ReplacementCharacter)) text = QString::fromLatin1(data);
    return text;
}

QString SchoolApp::logoUrl() const
{
    const QString u = photoUrl(setting("school_logo"));
    return u.isEmpty() ? QStringLiteral("qrc:/assets/logo.png") : u;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QString studentsCsvTemplate() const;\n', '''    Q_INVOKABLE QString studentsCsvTemplate() const;
    Q_INVOKABLE QVariantMap importTeachersCsv(const QString &csv);
    Q_INVOKABLE QString readTextFile(const QString &fileUrl) const;
    Q_INVOKABLE QString logoUrl() const;
''')

sfp = 'qml/pages/StudentFormPage.qml'
s = open(sfp, encoding='utf-8').read()
s = s.replace('        if (!/^\\d{4}-\\d{2}-\\d{2}$/.test(birthDate.text)) {', '        if (!isDateText(birthDate.text)) {')
s = s.replace('        if (!/^\\d{4}-\\d{2}-\\d{2}$/.test(entryDate.text)) {', '        if (!isDateText(entryDate.text)) {')
s = s.replace('La date de naissance doit être au format AAAA-MM-JJ.', 'La date de naissance doit être au format JJ-MM-AAAA.')
s = s.replace("La date d'entrée doit être au format AAAA-MM-JJ.", "La date d'entrée doit être au format JJ-MM-AAAA.")
s = s.replace('birthDate:birthDate.text', 'birthDate:toIso(birthDate.text)')
s = s.replace('entryDate:entryDate.text', 'entryDate:toIso(entryDate.text)')
s = s.replace('    function save() {\n', '''    function isDateText(t) {
        return /^\\d{4}-\\d{2}-\\d{2}$/.test(t) || /^\\d{2}[-\\/.]\\d{2}[-\\/.]\\d{4}$/.test(t)
    }
    function toIso(t) {
        var m = /^(\\d{2})[-\\/.](\\d{2})[-\\/.](\\d{4})$/.exec(t)
        return m ? m[3] + "-" + m[2] + "-" + m[1] : t
    }

    function save() {
''', 1)
open(sfp, 'w', encoding='utf-8').write(s)

for f in glob.glob('qml/pages/*.qml') + glob.glob('qml/components/*.qml'):
    t = open(f, encoding='utf-8').read()
    if 'AAAA-MM-JJ' in t:
        open(f, 'w', encoding='utf-8').write(t.replace('AAAA-MM-JJ', 'JJ-MM-AAAA'))

sb = 'qml/components/Sidebar.qml'
edit(sb, '    property string myPhotoUrl: ""\n', '    property string myPhotoUrl: ""\n    property string logoSource: "qrc:/assets/logo.png"\n')
edit(sb, '        myPhotoUrl = school.photoUrl(school.myPhoto())\n', '        myPhotoUrl = school.photoUrl(school.myPhoto())\n        logoSource = school.logoUrl()\n')
edit(sb, '            source: "qrc:/assets/logo.png"\n', '            source: root.logoSource\n')

sp = 'qml/pages/SettingsPage.qml'
s = open(sp, encoding='utf-8').read()
idx = s.index('implicitHeight: thresholdColumn.implicitHeight + 40')
start = s.rfind('            Rectangle {', 0, idx)
block = '''            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: logoColumn.implicitHeight + 40
                ColumnLayout {
                    id: logoColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 10
                    Label { text: "Logo de l'établissement"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Ce logo apparaît dans le menu latéral. Formats JPG ou PNG."; color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    PhotoPicker {
                        size: 120
                        path: school.setting("school_logo")
                        onPhotoChanged: function(p) { school.setSetting("school_logo", p) }
                    }
                }
            }

'''
s = s[:start] + block + s[start:]
open(sp, 'w', encoding='utf-8').write(s)

ip = 'qml/pages/ImportPage.qml'
edit(ip, 'import QtQuick.Layouts\n', 'import QtQuick.Layouts\nimport QtQuick.Dialogs\n')
edit(ip, '                    Label { text: "Données à importer :"; font.bold: true }\n', '''                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Label { text: "Type :" }
                        ComboBox { id: importType; Layout.preferredWidth: 200; model: ["Élèves", "Enseignants"] }
                        AppButton { text: "Choisir un fichier CSV…"; onClicked: fileDialog.open() }
                        Label {
                            text: "Excel : Enregistrer sous → CSV (séparateur ;). Access : exporter la table en CSV."
                            color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                    }
                    FileDialog {
                        id: fileDialog
                        nameFilters: ["Fichiers CSV (*.csv *.txt)"]
                        onAccepted: csvInput.text = school.readTextFile(selectedFile.toString())
                    }
                    Label { text: "Données à importer :"; font.bold: true }
''')
edit(ip, 'onClicked: root.result = school.importStudentsCsv(csvInput.text)',
     'onClicked: root.result = importType.currentIndex === 0 ? school.importStudentsCsv(csvInput.text) : school.importTeachersCsv(csvInput.text)')
edit(ip, 'text: "Élèves importés : " + (root.result.imported || 0)',
     'text: (importType.currentIndex === 0 ? "Élèves importés : " : "Enseignants importés : ") + (root.result.imported || 0)')

edit('CMakeLists.txt', '        qml/components/ConfirmDelete.qml\n', '        qml/components/ConfirmDelete.qml\n')
print("dates, logo et importation appliqués")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: dates JJ-MM-AAAA acceptées, logo modifiable dans les paramètres, importation CSV depuis fichier (élèves et enseignants)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-dates-logo-import."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-dates-logo-import"
