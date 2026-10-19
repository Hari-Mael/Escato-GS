#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -f qml/pages/StudentFormPage.qml ] || [ ! -f qml/pages/AccountsPage.qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-corrections-enregistrement main
git rm -q --ignore-unmatch install-*.sh || true

cat > qml/components/ConfirmDelete.qml <<'QML'
import QtQuick
import QtQuick.Controls

Dialog {
    id: root
    property string message: "Confirmer la suppression ?"
    property int targetId: 0
    signal confirmed(int id)

    title: "Confirmer la suppression"
    modal: true
    anchors.centerIn: Overlay.overlay
    standardButtons: Dialog.Yes | Dialog.No
    width: 380

    Label {
        width: parent.width
        text: root.message
        wrapMode: Text.WordWrap
    }

    function ask(id) {
        targetId = id || 0
        open()
    }

    onAccepted: confirmed(targetId)
}
QML

cat > qml/pages/TeachersPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    signal createRequested()
    property var rows: []
    property string searchText: ""

    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ConfirmDelete {
        id: confirmDel
        message: "Supprimer cet enseignant ? Son compte ne pourra plus se connecter."
        onConfirmed: function(id) { school.deleteTeacher(id) }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 15

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Enseignants"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            AppButton { text: "➕ Ajouter"; onClicked: createRequested() }
        }

        AppTextField {
            Layout.fillWidth: true
            placeholderText: "Rechercher enseignant, matière, CIN..."
            onTextChanged: searchText = text
            onEditingFinished: refresh()
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: rows
            clip: true
            delegate: Rectangle {
                width: parent.width
                height: 65
                color: index % 2 ? "#FAFBFC" : "white"
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    Label { text: modelData.name; width: 170; elide: Text.ElideRight }
                    Label { text: modelData.email; width: 210; elide: Text.ElideRight }
                    Label { text: modelData.subject; width: 160; elide: Text.ElideRight }
                    Label { text: modelData.contact; width: 140 }
                    Label { text: modelData.status; width: 90 }
                    AppButton { text: "Supprimer"; onClicked: confirmDel.ask(modelData.id) }
                }
            }
        }
    }

    function refresh() { rows = school.teachers(searchText) }
}
QML

python3 <<'PY'
import re

def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

def regex_edit(path, pattern, repl, count=1):
    s = open(path, encoding='utf-8').read()
    s, n = re.subn(pattern, repl, s, count=count, flags=re.S)
    assert n == count, (path, n, pattern[:60])
    open(path, 'w', encoding='utf-8').write(s)

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE bool deleteTeacher(int id);\n', '    Q_INVOKABLE bool deleteTeacher(int id);\n    Q_INVOKABLE bool deleteUser(int id);\n')

cpp = 'src/core/SchoolApp.cpp'
edit(cpp, '    if(!q.exec()){db.rollback();return false;}int uid=q.lastInsertId().toInt();',
     '    if(!q.exec()){db.rollback();emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cet e-mail est déjà utilisé par un autre compte.") : q.lastError().text());return false;}int uid=q.lastInsertId().toInt();')
s = open(cpp, encoding='utf-8').read()
s += '''
bool SchoolApp::deleteUser(int id)
{
    if (!can("users.manage")) return false;
    if (id == m_userId) {
        emit errorOccurred(QStringLiteral("Vous ne pouvez pas supprimer votre propre compte."));
        return false;
    }
    QSqlQuery role(m_db.db());
    role.prepare("SELECT role FROM users WHERE id=? AND deleted_at IS NULL");
    role.addBindValue(id);
    if (!role.exec() || !role.next()) {
        emit errorOccurred(QStringLiteral("Utilisateur introuvable."));
        return false;
    }
    if (role.value(0).toString() == QLatin1String("administrateur")) {
        QSqlQuery admins(m_db.db());
        admins.prepare("SELECT COUNT(*) FROM users WHERE role='administrateur' AND deleted_at IS NULL AND id<>?");
        admins.addBindValue(id);
        if (!admins.exec() || !admins.next() || admins.value(0).toInt() == 0) {
            emit errorOccurred(QStringLiteral("Impossible : c'est le dernier administrateur."));
            return false;
        }
    }
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE users SET deleted_at=CURRENT_TIMESTAMP, account_status='blocked', blocked_reason='Compte supprimé' WHERE id=? AND deleted_at IS NULL");
    q.addBindValue(id);
    if (!q.exec() || q.numRowsAffected() != 1) {
        emit errorOccurred(q.lastError().text().isEmpty() ? QStringLiteral("Suppression impossible.") : q.lastError().text());
        return false;
    }
    audit("delete", "user", id);
    emit dataChanged();
    return true;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sfp = 'qml/pages/StudentFormPage.qml'
s = open(sfp, encoding='utf-8').read()
s = s.replace('Label{text:', 'Label{Layout.preferredWidth:230;text:')
s = s.replace('        ScrollView {\n            Layout.fillWidth:true; Layout.fillHeight:true\n', '        ScrollView {\n            Layout.fillWidth:true; Layout.fillHeight:true\n            contentWidth: availableWidth\n', 1)
open(sfp, 'w', encoding='utf-8').write(s)
edit(sfp, '    function formData() {\n',
     '''    ConfirmDelete {
        id: confirmDelete
        message: "Supprimer cet élève ? Il ne figurera plus dans les listes."
        onConfirmed: function(id) { if (school.deleteStudent(id)) saved() }
    }

    function formData() {
''')
regex_edit(sfp, r'(                AppButton \{\n\s*Layout\.columnSpan:2; Layout\.alignment:Qt\.AlignRight)',
           '''                AppButton {
                    Layout.columnSpan:2; Layout.alignment:Qt.AlignLeft
                    visible: editingId > 0
                    text: "Supprimer l'élève"
                    palette.button: "#C62828"
                    onClicked: confirmDelete.ask(editingId)
                }
                AppButton {
                    Layout.columnSpan:2; Layout.alignment:Qt.AlignRight''')
edit(sfp, '        var ok = editingId ? school.updateStudent(editingId,formData()) : school.addStudent(formData())\n        if(ok) { reset(); saved() }',
     '        var ok = editingId ? school.updateStudent(editingId,formData()) : school.addStudent(formData())\n        if(ok) { reset(); saved() }\n        else formError.text = "Enregistrement impossible : vérifie les champs (matricule déjà utilisé ?)."')

tfp = 'qml/pages/TeacherFormPage.qml'
edit(tfp, '        if(school.addTeacher(formData())){reset();saved()}',
     '        if(school.addTeacher(formData())){reset();saved()}\n        else formError.text="Enregistrement impossible : e-mail déjà utilisé ou champs invalides."')

cp = 'qml/pages/CoursesPage.qml'
edit(cp, '    Dialog{id:form;title:"Créer un cours"',
     '    ConfirmDelete{id:confirmDel;message:"Supprimer ce cours ?";onConfirmed:function(id){school.deleteCourse(id)}}\n    Dialog{id:form;title:"Créer un cours"')
edit(cp, 'Label{text:modelData.description;width:250}',
     'Label{text:modelData.description;width:200}\n                    AppButton{text:"Supprimer";onClicked:confirmDel.ask(modelData.id)}')

ap = 'qml/pages/AccountsPage.qml'
regex_edit(ap, r'(onClicked: school\.unblockUser\(modelData\.id\)\n\s*\}\n)',
           r'\1                    AppButton { text: "Supprimer"; visible: school.can("users.manage"); onClicked: confirmDel.ask(modelData.id) }\n')
edit(ap, '    Dialog {\n        id: create',
     '    ConfirmDelete {\n        id: confirmDel\n        message: "Supprimer cet utilisateur ? Il ne pourra plus se connecter."\n        onConfirmed: function(id) { school.deleteUser(id) }\n    }\n\n    Dialog {\n        id: create')

edit('CMakeLists.txt', '        qml/components/PhotoPicker.qml\n', '        qml/components/PhotoPicker.qml\n        qml/components/ConfirmDelete.qml\n')
print("corrections appliquées")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "fix: enregistrements signalés en cas d'échec, suppression d'utilisateurs, cours, enseignants et élèves, formulaire élève aligné"

echo ""
echo "Commit créé sur la branche feat/escato-gs-corrections-enregistrement."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-corrections-enregistrement"
