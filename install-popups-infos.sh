#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -f qml/pages/StudentsPage.qml ] || [ ! -f qml/pages/TeachersPage.qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-popups-infos main
git rm -q --ignore-unmatch install-*.sh || true

cat > qml/components/InfoPopup.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    property string heading: ""
    property var items: []

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    padding: 24
    width: 470
    background: Rectangle { radius: 14; color: "white" }

    function fmtAny(v) {
        var s = String(v === undefined || v === null ? "" : v)
        var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s)
        return m ? m[3] + "-" + m[2] + "-" + m[1] : s
    }
    function show(title, list) {
        heading = title
        items = list.map(function(p) { return [p[0], fmtAny(p[1])] })
        open()
    }

    ColumnLayout {
        width: root.width - root.padding * 2
        spacing: 10

        Label {
            text: root.heading
            font.pixelSize: 20
            font.bold: true
            color: "#0B2A43"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#E3E8EE" }

        Repeater {
            model: root.items
            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Label {
                    text: modelData[0]
                    color: "#667085"
                    Layout.preferredWidth: 170
                    wrapMode: Text.WordWrap
                }
                Label {
                    text: (modelData[1] === "" || modelData[1] === null) ? "—" : modelData[1]
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
        }

        AppButton {
            text: "Fermer"
            Layout.alignment: Qt.AlignRight
            onClicked: root.close()
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

sp = 'qml/pages/StudentsPage.qml'
s = open(sp, encoding='utf-8').read()
clickable = lambda field, w: ('Label { text:modelData.%s; width:%s; color:"#0B7F74"; font.underline:true\n'
                              '                            MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked: infoPopup.show(modelData.lastName + " " + modelData.firstName, studentInfo(modelData)) } }') % (field, w)
s, n1 = re.subn(r'Label \{ text:modelData\.lastName; width:150 \}', clickable('lastName', 150), s)
s, n2 = re.subn(r'Label \{ text:modelData\.firstName; width:150 \}', clickable('firstName', 150), s)
assert n1 == 1 and n2 == 1, (n1, n2)
open(sp, 'w', encoding='utf-8').write(s)

info = '''    InfoPopup { id: infoPopup }

    function studentInfo(s) {
        return [
            ["Matricule", s.matricule],
            ["Nom", s.lastName],
            ["Prénom", s.firstName],
            ["Date de naissance", s.birthDate],
            ["Lieu de naissance", s.birthPlace],
            ["Classe", s.className],
            ["Date d'entrée", s.entryDate],
            ["Téléphone parent", s.parentPhone],
            ["E-mail parent", s.parentEmail],
            ["Adresse", s.address],
            ["Ancienne école", s.previousSchool],
            ["Ancienne classe", s.previousClass],
            ["Projet / carrière", s.desiredCareer],
            ["Statut du compte", s.accountStatus],
            ["Paiements manqués", s.missedPayments]
        ]
    }

    function refresh() { rows = school.students'''
edit(sp, '    function refresh() { rows = school.students', info)

tp = 'qml/pages/TeachersPage.qml'
s = open(tp, encoding='utf-8').read()
old_name = 'Label { text: modelData.name; width: 160; elide: Text.ElideRight }'
assert s.count(old_name) == 1
s = s.replace(old_name, '''Label {
                        text: modelData.name; width: 160; elide: Text.ElideRight
                        color: "#0B7F74"; font.underline: true
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: infoPopup.show(modelData.name, teacherInfo(modelData)) }
                    }''')
open(tp, 'w', encoding='utf-8').write(s)
edit(tp, '    function refresh() { rows = school.teachers(searchText) }', '''    InfoPopup { id: infoPopup }

    function teacherInfo(t) {
        return [
            ["E-mail", t.email],
            ["Statut du compte", t.status],
            ["CIN", t.cin],
            ["CNAPS", t.cnaps],
            ["Numéro MLE", t.mle],
            ["Contact", t.contact],
            ["Adresse", t.address],
            ["Date de naissance", t.dob],
            ["Lieu de naissance", t.birthPlace],
            ["Matière", t.subject],
            ["Profession", t.occupation],
            ["Type d'emploi", t.employmentType],
            ["Situation matrimoniale", t.maritalStatus],
            ["Nombre d'enfants", t.children],
            ["Religion", t.religion]
        ]
    }

    function refresh() { rows = school.teachers(searchText) }''')

edit('CMakeLists.txt', '        qml/components/ConfirmDelete.qml\n', '        qml/components/ConfirmDelete.qml\n        qml/components/InfoPopup.qml\n')
print("fenêtres d'informations appliquées")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: clic sur le nom ou le prénom d'un élève ou d'un enseignant ouvre une fenêtre d'informations"

echo ""
echo "Commit créé sur la branche feat/escato-gs-popups-infos."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-popups-infos"
