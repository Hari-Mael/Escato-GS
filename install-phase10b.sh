#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-coefficients-seuils main
git rm -q --ignore-unmatch install-phase*.sh || true

python3 <<'PY'
def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

db = 'src/core/Database.cpp'
edit(db, 'bool Database::seed()\n{\n', '''bool Database::seed()
{
    if (!exec("INSERT OR IGNORE INTO settings(key,value) VALUES ('pass_mark','10'),('retake_mark','8')"))
        return false;

''')

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE bool deleteSubject(int id);\n', '    Q_INVOKABLE bool deleteSubject(int id);\n    Q_INVOKABLE bool updateSubject(int id, const QVariantMap &v);\n')

cpp = 'src/core/SchoolApp.cpp'
edit(cpp, 'bool SchoolApp::deleteSubject(int id)\n', '''bool SchoolApp::updateSubject(int id, const QVariantMap &v)
{
    if (!can("subjects.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const double coef = v.value("coefficient").toDouble();
    if (name.isEmpty() || coef <= 0) {
        emit errorOccurred(QStringLiteral("Nom et coefficient (> 0) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE subjects SET name=?, coefficient=? WHERE id=?");
    q.addBindValue(name);
    q.addBindValue(coef);
    q.addBindValue(id);
    if (!q.exec()) {
        emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette matière existe déjà.") : q.lastError().text());
        return false;
    }
    audit("update", "subject", id, name + " coef " + QString::number(coef));
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteSubject(int id)
''')

edit(cpp, '            m["decision"] = avg >= 10 ? QStringLiteral("Admis") : avg >= 8 ? QStringLiteral("Rattrapage") : QStringLiteral("Ajourné");\n',
     '''            const double passMark = setting("pass_mark").isEmpty() ? 10.0 : setting("pass_mark").toDouble();
            const double retakeMark = setting("retake_mark").isEmpty() ? 8.0 : setting("retake_mark").toDouble();
            m["decision"] = avg >= passMark ? QStringLiteral("Admis") : avg >= retakeMark ? QStringLiteral("Rattrapage") : QStringLiteral("Ajourné");
''')

cp = 'qml/pages/CurriculumPage.qml'
edit(cp, '                            Label { text: "coef. " + modelData.coefficient; color: "#667085" }\n',
     '''                            AppTextField { id: coefEdit; text: String(modelData.coefficient); Layout.preferredWidth: 110; inputMethodHints: Qt.ImhDigitsOnly }
                            AppButton {
                                text: "Enregistrer"
                                onClicked: school.updateSubject(modelData.id, {name: modelData.name, coefficient: parseFloat(coefEdit.text.replace(",", ".")) || 0})
                            }
''')

sp = 'qml/pages/SettingsPage.qml'
s = open(sp, encoding='utf-8').read()
idx = s.index('implicitHeight: periodColumn.implicitHeight + 40')
start = s.rfind('            Rectangle {', 0, idx)
block = '''            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: thresholdColumn.implicitHeight + 40

                ColumnLayout {
                    id: thresholdColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10
                    Label { text: "Seuils de décision des délibérations"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Moyenne sur 20 : admis à partir du premier seuil, rattrapage à partir du second, ajourné en dessous."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Label { text: "Admis à partir de" }
                        AppTextField { id: passMark; Layout.preferredWidth: 110; enabled: root.canSettings; inputMethodHints: Qt.ImhDigitsOnly }
                        Label { text: "Rattrapage à partir de" }
                        AppTextField { id: retakeMark; Layout.preferredWidth: 110; enabled: root.canSettings; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Enregistrer"
                            highlighted: true
                            visible: root.canSettings
                            onClicked: {
                                school.setSetting("pass_mark", passMark.text.replace(",", "."))
                                school.setSetting("retake_mark", retakeMark.text.replace(",", "."))
                            }
                        }
                    }
                }
            }

'''
s = s[:start] + block + s[start:]
open(sp, 'w', encoding='utf-8').write(s)
edit(sp, '        refreshPerms()\n        refreshPeriods()\n    }\n',
     '        refreshPerms()\n        refreshPeriods()\n        passMark.text = school.setting("pass_mark")\n        retakeMark.text = school.setting("retake_mark")\n    }\n')

cl = 'qml/pages/CouncilPage.qml'
edit(cl, 'Label { text: "Admis : moyenne ≥ 10 · Rattrapage : 8 à 10 · Ajourné : < 8"; color: "#667085" }',
     'Label { text: "Admis : moyenne ≥ " + school.setting("pass_mark") + " · Rattrapage : ≥ " + school.setting("retake_mark") + " · Ajourné : < " + school.setting("retake_mark"); color: "#667085" }')
print("coefficients et seuils appliqués")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: coefficients des matières modifiables, seuils de décision paramétrables dans les délibérations"

echo ""
echo "Commit créé sur la branche feat/escato-gs-coefficients-seuils."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-coefficients-seuils"
