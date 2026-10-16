#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -f qml/components/Sidebar.qml ] || [ ! -f qml/pages/StudentFormPage.qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-photos main
git rm -q --ignore-unmatch install-*.sh || true

cat > qml/components/PhotoPicker.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: root
    property string path: ""
    property int size: 120
    signal photoChanged(string newPath)

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(size, row.implicitHeight)

    RowLayout {
        id: row
        spacing: 16

        Rectangle {
            Layout.preferredWidth: root.size
            Layout.preferredHeight: root.size
            radius: 12
            color: "#E6F6F4"
            clip: true

            Image {
                anchors.fill: parent
                source: school.photoUrl(root.path)
                visible: root.path !== ""
                fillMode: Image.PreserveAspectCrop
                smooth: true
                mipmap: true
            }
            Text {
                anchors.centerIn: parent
                visible: root.path === ""
                text: "Aucune photo"
                color: "#667085"
                font.pixelSize: 12
            }
        }

        ColumnLayout {
            spacing: 8
            AppButton {
                text: "Changer la photo"
                highlighted: true
                onClicked: dialog.open()
            }
            AppButton {
                text: "Retirer la photo"
                visible: root.path !== ""
                onClicked: {
                    root.path = ""
                    root.photoChanged("")
                }
            }
        }
    }

    FileDialog {
        id: dialog
        title: "Choisir une photo"
        nameFilters: ["Images (*.jpg *.jpeg *.png)"]
        onAccepted: {
            const stored = school.importPhoto(selectedFile.toString())
            if (stored !== "") {
                root.path = stored
                root.photoChanged(stored)
            }
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

def regex_once(path, pattern, repl):
    s = open(path, encoding='utf-8').read()
    s, n = re.subn(pattern, repl, s, count=1, flags=re.S)
    assert n == 1, (path, pattern[:60])
    open(path, 'w', encoding='utf-8').write(s)

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QString studentsCsvTemplate() const;\n', '''    Q_INVOKABLE QString studentsCsvTemplate() const;
    Q_INVOKABLE QString importPhoto(const QString &fileUrl) const;
    Q_INVOKABLE QString photoUrl(const QString &path) const;
    Q_INVOKABLE QString myPhoto() const;
    Q_INVOKABLE bool setMyPhoto(const QString &path);
    Q_INVOKABLE QString studentPhotoPath(int studentId) const;
''')

db = 'src/core/Database.cpp'
edit(db, '    if (!columnExists(QStringLiteral("payments"), QStringLiteral("receipt_number"))',
     '    if (!columnExists(QStringLiteral("users"), QStringLiteral("photo"))\n        && !exec("ALTER TABLE users ADD COLUMN photo TEXT"))\n        return false;\n\n    if (!columnExists(QStringLiteral("payments"), QStringLiteral("receipt_number"))')

cpp = 'src/core/SchoolApp.cpp'
edit(cpp, '#include <QSet>\n', '#include <QSet>\n#include <QStandardPaths>\n#include <QDir>\n#include <QUuid>\n#include <QUrl>\n#include <QFile>\n#include <QImage>\n')
s = open(cpp, encoding='utf-8').read()
s += '''
QString SchoolApp::importPhoto(const QString &fileUrl) const
{
    if (m_userId <= 0) return QString();
    const QUrl url(fileUrl);
    const QString local = url.isLocalFile() ? url.toLocalFile() : fileUrl;
    QImage img(local);
    if (img.isNull()) return QString();
    if (img.width() > 400 || img.height() > 400)
        img = img.scaled(400, 400, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    const QString dirPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/photos");
    QDir().mkpath(dirPath);
    const QString target = dirPath + QStringLiteral("/") + QUuid::createUuid().toString(QUuid::WithoutBraces) + QStringLiteral(".jpg");
    if (!img.save(target, "JPG", 85)) return QString();
    return target;
}

QString SchoolApp::photoUrl(const QString &path) const
{
    if (path.trimmed().isEmpty() || !QFile::exists(path)) return QString();
    return QUrl::fromLocalFile(path).toString();
}

QString SchoolApp::myPhoto() const
{
    if (m_userId <= 0) return QString();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE(photo,'') FROM users WHERE id=?");
    q.addBindValue(m_userId);
    return q.exec() && q.next() ? q.value(0).toString() : QString();
}

bool SchoolApp::setMyPhoto(const QString &path)
{
    if (m_userId <= 0) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE users SET photo=? WHERE id=?");
    q.addBindValue(path.trimmed().isEmpty() ? QVariant() : QVariant(path));
    q.addBindValue(m_userId);
    if (!q.exec()) return false;
    audit("update", "user_photo", m_userId, path.trimmed().isEmpty() ? QStringLiteral("retirée") : QStringLiteral("modifiée"));
    emit dataChanged();
    return true;
}

QString SchoolApp::studentPhotoPath(int studentId) const
{
    if (!canViewStudent(studentId)) return QString();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE(photo,'') FROM students WHERE id=?");
    q.addBindValue(studentId);
    return q.exec() && q.next() ? q.value(0).toString() : QString();
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sfp = 'qml/pages/StudentFormPage.qml'
regex_once(sfp, r'(\n\s*GridLayout \{\n)', r'\1                PhotoPicker { id: photoPicker; Layout.columnSpan: 2 }\n')
edit(sfp, 'photo:"",', 'photo:photoPicker.path,')
edit(sfp, '    property int editingId: 0\n', '    property int editingId: 0\n    onEditingIdChanged: photoPicker.path = editingId ? school.studentPhotoPath(editingId) : ""\n')
edit(sfp, '    function reset() {\n', '    function reset() {\n        photoPicker.path = ""\n')

tfp = 'qml/pages/TeacherFormPage.qml'
regex_once(tfp, r'(\n\s*GridLayout\{width:parent\.width;columns:2;columnSpacing:18;rowSpacing:12\n)', r'\1                PhotoPicker{id:photoPicker;Layout.columnSpan:2}\n')
s = open(tfp, encoding='utf-8').read()
m = re.search(r'function formData\(\)\{return\{', s)
assert m
if 'photo:' in s[m.end():m.end()+4000].split('}', 1)[0]:
    s = re.sub(r'(function formData\(\)\{return\{[^}]*?)photo:[^,}]*', lambda mm: mm.group(1) + 'photo:photoPicker.path', s, count=1)
else:
    s = s[:m.end()] + 'photo:photoPicker.path,' + s[m.end():]
open(tfp, 'w', encoding='utf-8').write(s)
edit(tfp, 'function reset(){', 'function reset(){photoPicker.path="";')

sb = 'qml/components/Sidebar.qml'
edit(sb, '    property string currentPage: "dashboard"\n', '    property string currentPage: "dashboard"\n    property string myPhotoUrl: ""\n')
edit(sb, '    function refreshPerms() {\n        perms = {', '    function refreshPerms() {\n        myPhotoUrl = school.photoUrl(school.myPhoto())\n        perms = {')
edit(sb, '    ColumnLayout {\n        anchors.fill: parent\n        anchors.margins: 14', '''    Popup {
        id: profilePopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 360
        padding: 24
        background: Rectangle { radius: 14; color: "white" }

        ColumnLayout {
            spacing: 14
            Label { text: "Ma photo de profil"; font.pixelSize: 18; font.bold: true }
            PhotoPicker {
                id: myPicker
                size: 140
                path: school.myPhoto()
                onPhotoChanged: function(newPath) { school.setMyPhoto(newPath) }
            }
            AppButton { text: "Fermer"; Layout.alignment: Qt.AlignRight; onClicked: profilePopup.close() }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14''')
regex_once(sb, r'(                Layout\.preferredWidth: 36\n                Layout\.preferredHeight: 36\n                radius: 18\n                color: "#0F9D8F"\n)',
           r'''                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 10
                color: "#0F9D8F"
                clip: true

                Image {
                    anchors.fill: parent
                    source: root.myPhotoUrl
                    visible: root.myPhotoUrl !== ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: profilePopup.open()
                }
''')
s = open(sb, encoding='utf-8').read()
s, n = re.subn(r'^([ \t]*)text: root\.initials\(school\.currentUser\)\n',
               lambda mm: mm.group(0) + mm.group(1) + 'visible: root.myPhotoUrl === ""\n', s, count=1, flags=re.M)
assert n == 1
open(sb, 'w', encoding='utf-8').write(s)

edit('CMakeLists.txt', '        qml/components/Icon.qml\n', '        qml/components/Icon.qml\n        qml/components/PhotoPicker.qml\n')
print("photos appliquées")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: photos de profil (élèves, enseignants, comptes connectés), importation et redimensionnement, avatar du menu"

echo ""
echo "Commit créé sur la branche feat/escato-gs-photos."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-photos"
