#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -f src/core/PrintManager.cpp ] || [ ! -f qml/pages/TeachersPage.qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-qr-informations main
git rm -q --ignore-unmatch install-*.sh || true

cat > qml/pages/TeachersPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    signal createRequested()
    property var rows: []
    property string searchText: ""
    property int qrId: 0

    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ConfirmDelete {
        id: confirmDel
        message: "Supprimer cet enseignant ? Son compte ne pourra plus se connecter."
        onConfirmed: function(id) { school.deleteTeacher(id) }
    }

    Popup {
        id: qrPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        padding: 20
        background: Rectangle { radius: 14; color: "white" }

        ColumnLayout {
            spacing: 12
            Label { text: "QR code enseignant"; font.pixelSize: 18; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 260
                Layout.preferredHeight: 260
                fillMode: Image.PreserveAspectFit
                smooth: false
                source: school.qrCodePngDataUrl(school.teacherQrText(qrId))
            }
            Label {
                text: "Scanner ce code affiche les informations de l'enseignant (nom, matière, contact)."
                color: "#667085"
                wrapMode: Text.WordWrap
                Layout.preferredWidth: 280
            }
            AppButton { text: "Fermer"; Layout.alignment: Qt.AlignRight; onClicked: qrPopup.close() }
        }
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
                    Label { text: modelData.name; width: 160; elide: Text.ElideRight }
                    Label { text: modelData.email; width: 190; elide: Text.ElideRight }
                    Label { text: modelData.subject; width: 130; elide: Text.ElideRight }
                    Label { text: modelData.contact; width: 130 }
                    Label { text: modelData.status; width: 80 }
                    AppButton { text: "QR"; onClicked: { qrId = modelData.id; qrPopup.open() } }
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

pm = 'src/core/PrintManager.cpp'
s = open(pm, encoding='utf-8').read()
i = s.index('SELECT matricule,last_name,first_name,current_class,photo FROM students WHERE id=?')
j = s.index('    const QString matricule = q.value(0).toString();\n', i)
insert = ('    const QString qrPayload = QStringLiteral("ESCATO GS - ÉLÈVE\\nMatricule : %1\\nNom : %2 %3\\nClasse : %4")\n'
          '        .arg(matricule, q.value(1).toString(), q.value(2).toString(), q.value(3).toString());\n')
j_end = j + len('    const QString matricule = q.value(0).toString();\n')
s = s[:j_end] + insert + s[j_end:]
assert s.count('qrcodegen::QrCode::encodeText(matricule.toUtf8().constData(),') == 1
s = s.replace('qrcodegen::QrCode::encodeText(matricule.toUtf8().constData(),', 'qrcodegen::QrCode::encodeText(qrPayload.toUtf8().constData(),')
open(pm, 'w', encoding='utf-8').write(s)

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE bool deleteUser(int id);\n', '''    Q_INVOKABLE bool deleteUser(int id);
    Q_INVOKABLE QString teacherQrText(int userId) const;
    Q_INVOKABLE QString qrCodePngDataUrl(const QString &text) const;
''')

cpp = 'src/core/SchoolApp.cpp'
edit(cpp, '#include <QSet>\n', '#include <QSet>\n#include <QImage>\n#include <QBuffer>\n#include "third_party/qrcodegen/qrcodegen.hpp"\n')
s = open(cpp, encoding='utf-8').read()
s += '''
QString SchoolApp::teacherQrText(int userId) const
{
    if (!(can("teachers.manage") || can("students.view"))) return QString();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT u.name,u.email,COALESCE(t.subject,''),COALESCE(t.contact,'') FROM users u "
              "LEFT JOIN teacher_profiles t ON t.user_id=u.id WHERE u.id=? AND u.deleted_at IS NULL");
    q.addBindValue(userId);
    if (!q.exec() || !q.next()) return QString();
    return QStringLiteral("ESCATO GS - ENSEIGNANT\\nNom : %1\\nMatière : %2\\nContact : %3\\nE-mail : %4")
        .arg(q.value(0).toString(), q.value(2).toString(), q.value(3).toString(), q.value(1).toString());
}

QString SchoolApp::qrCodePngDataUrl(const QString &text) const
{
    const QString t = text.trimmed();
    if (t.isEmpty()) return QString();
    const qrcodegen::QrCode qr = qrcodegen::QrCode::encodeText(t.toUtf8().constData(), qrcodegen::QrCode::Ecc::MEDIUM);
    const int border = 4;
    const int size = qr.getSize();
    QImage img(size + 2 * border, size + 2 * border, QImage::Format_RGB32);
    img.fill(Qt::white);
    for (int y = 0; y < size; ++y)
        for (int x = 0; x < size; ++x)
            if (qr.getModule(x, y)) img.setPixel(x + border, y + border, qRgb(0, 0, 0));
    img = img.scaled(img.width() * 6, img.height() * 6, Qt::KeepAspectRatio, Qt::FastTransformation);
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    img.save(&buffer, "PNG");
    return QStringLiteral("data:image/png;base64,") + QString::fromLatin1(bytes.toBase64());
}
'''
open(cpp, 'w', encoding='utf-8').write(s)
print("QR informations appliqués")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: QR codes qui affichent les informations de l'élève (carte) et de l'enseignant (fiche liste)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-qr-informations."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-qr-informations"
