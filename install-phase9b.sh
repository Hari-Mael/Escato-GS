#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-filtre-statut-eleves main
git rm -q --ignore-unmatch install-phase*.sh || true

python3 <<'PY'
def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

sp = 'qml/pages/StudentsPage.qml'
edit(sp, '    property var rows: []\n', '''    property var rows: []
    property int statusIndex: 0

    function matchesStatus(s) {
        var graduated = !!s.graduatedAt
        var active = (s.accountStatus || "active") === "active"
        if (statusIndex === 1) return !graduated && active
        if (statusIndex === 2) return !graduated && !active
        if (statusIndex === 3) return graduated
        return true
    }
''')
edit(sp, '    function refresh() { rows = school.students(selectedClass, searchText) }\n',
     '    function refresh() { rows = school.students(selectedClass, searchText).filter(matchesStatus) }\n')
edit(sp, '            AppButton { text: "Actualiser"; onClicked: refresh() }\n',
     '''            ComboBox {
                Layout.preferredWidth: 170
                model: ["Tous les statuts", "Actifs", "Bloqués", "Diplômés"]
                onCurrentIndexChanged: { statusIndex = currentIndex; refresh() }
            }
            AppButton { text: "Actualiser"; onClicked: refresh() }
''')
print("filtre statut appliqué")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: filtre par statut (actifs, bloqués, diplômés) sur la liste des élèves"

echo ""
echo "Commit créé sur la branche feat/escato-gs-filtre-statut-eleves."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-filtre-statut-eleves"
