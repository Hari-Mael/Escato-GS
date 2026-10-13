#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-affichage-droits main
git rm -q --ignore-unmatch install-phase4.sh install-phase5.sh install-phase6.sh install-phase7.sh install-phase8.sh || true

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

sb = 'qml/components/Sidebar.qml'
edit(sb, '    signal navigate(string page)\n', '''    signal navigate(string page)

    property var perms: ({})
    function refreshPerms() {
        perms = {
            "audit": school.can("audit.view"),
            "fees": school.can("balances.view"),
            "roles": school.can("roles.manage")
        }
    }
    function pageAllowed(p) {
        return p in perms ? perms[p] : true
    }
    Component.onCompleted: refreshPerms()
    Connections {
        target: school
        function onDataChanged() { root.refreshPerms() }
        function onSessionChanged() { root.refreshPerms() }
    }
''')
edit(sb, '                text: modelData[2] + "  " + modelData[1]\n',
     '                text: modelData[2] + "  " + modelData[1]\n                visible: root.pageAllowed(modelData[0])\n')

fp = 'qml/pages/FeesPage.qml'
edit(fp, '    property bool canEdit: school.currentRole === "administrateur" || school.currentRole === "comptable"\n',
     '    property bool canTuition: false\n    property bool canOneTime: false\n\n    function refreshPerms() {\n        canTuition = school.can("fees.tuition")\n        canOneTime = school.can("fees.onetime.manage")\n    }\n')
s = open(fp, encoding='utf-8').read()
assert s.count('root.canEdit') == 4, s.count('root.canEdit')
s = s.replace('root.canEdit', 'root.canTuition', 2).replace('root.canEdit', 'root.canOneTime')
open(fp, 'w', encoding='utf-8').write(s)
edit(fp, '    Component.onCompleted: { refreshTuitions(); refreshOverview(); refreshFeeTypes() }\n    Connections {\n        target: school\n        function onDataChanged() { root.refreshTuitions(); root.refreshOverview(); root.refreshFeeTypes() }\n    }\n',
     '    Component.onCompleted: { refreshPerms(); refreshTuitions(); refreshOverview(); refreshFeeTypes() }\n    Connections {\n        target: school\n        function onDataChanged() { root.refreshPerms(); root.refreshTuitions(); root.refreshOverview(); root.refreshFeeTypes() }\n        function onSessionChanged() { root.refreshPerms() }\n    }\n')

sp = 'qml/pages/SettingsPage.qml'
edit(sp, '    property bool isAdmin: school.currentRole === "administrateur"\n',
     '    property bool canSettings: false\n    property bool canPeriods: false\n\n    function refreshPerms() {\n        canSettings = school.can("settings.manage")\n        canPeriods = school.can("periods.manage")\n    }\n')
edit(sp, 'enabled: root.isAdmin', 'enabled: root.canSettings', count=3)
edit(sp, 'visible: root.isAdmin && !modelData.isActive', 'visible: root.canPeriods && !modelData.isActive')
edit(sp, '                        visible: root.isAdmin\n                        onClicked', '                        visible: root.canSettings\n                        onClicked')
edit(sp, '                        visible: root.isAdmin\n                        spacing: 8', '                        visible: root.canPeriods\n                        spacing: 8')
edit(sp, '        refreshPeriods()\n    }\n    Connections { target: school; function onDataChanged() { root.refreshPeriods() } }\n',
     '        refreshPerms()\n        refreshPeriods()\n    }\n    Connections {\n        target: school\n        function onDataChanged() { root.refreshPerms(); root.refreshPeriods() }\n        function onSessionChanged() { root.refreshPerms() }\n    }\n')

sd = 'qml/pages/StudentDetailPage.qml'
edit(sd, '    property var oneTimeRows: []\n', '''    property var oneTimeRows: []
    property bool canDelete: false
    property bool canBlock: false
    property bool canGuardAdd: false
    property bool canGuardRemove: false
    property bool canParents: false
    property bool canPay: false

    function refreshPerms() {
        canDelete = school.can("students.delete")
        canBlock = school.can("students.block")
        canGuardAdd = school.can("guardians.add")
        canGuardRemove = school.can("guardians.remove")
        canParents = school.can("parents.link")
        canPay = school.can("fees.onetime.pay")
    }
''')
edit(sd, '    function refresh() {\n', '    function refresh() {\n        refreshPerms()\n')
edit(sd, 'AppButton{text:"Diplômé";onClicked:', 'AppButton{text:"Diplômé";visible:root.canDelete;onClicked:')
edit(sd, 'AppButton{text:"Bloquer";onClicked:', 'AppButton{text:"Bloquer";visible:root.canBlock;onClicked:')
edit(sd, 'AppButton{text:"Débloquer";onClicked:', 'AppButton{text:"Débloquer";visible:root.canBlock;onClicked:')
edit(sd, 'AppButton{text:"Retirer"; onClicked: school.removeGuardian(modelData.linkId)}',
     'AppButton{text:"Retirer"; visible: root.canGuardRemove; onClicked: school.removeGuardian(modelData.linkId)}')
edit(sd, 'AppButton{text:"Retirer l\'accès"; onClicked: school.unlinkParent(modelData.linkId)}',
     'AppButton{text:"Retirer l\'accès"; visible: root.canParents; onClicked: school.unlinkParent(modelData.linkId)}')

s = open(sd, encoding='utf-8').read()
i = s.index('AppTextField{id:gName;')
j = s.rfind('RowLayout {', 0, i)
s = s[:j] + 'RowLayout {\n                        visible: root.canGuardAdd' + s[j + len('RowLayout {'):]
i = s.index('AppTextField{id:parentEmail;')
j = s.rfind('RowLayout {', 0, i)
s = s[:j] + 'RowLayout {\n                        visible: root.canParents' + s[j + len('RowLayout {'):]
open(sd, 'w', encoding='utf-8').write(s)

regex_edit(sd, r'visible: modelData\.status === "pending"(\s*)text: "Encaisser"',
           r'visible: root.canPay && modelData.status === "pending"\1text: "Encaisser"')
regex_edit(sd, r'visible: modelData\.status === "pending"(\s*)model: school\.paymentMethods\(\)',
           r'visible: root.canPay && modelData.status === "pending"\1model: school.paymentMethods()')
print("phase 8 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: affichage des boutons et menus selon la matrice des droits"

echo ""
echo "Commit créé sur la branche feat/escato-gs-affichage-droits."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-affichage-droits"
