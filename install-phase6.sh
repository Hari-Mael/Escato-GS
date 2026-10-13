#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-roles-permissions main
git rm -q --ignore-unmatch install-phase4.sh install-phase5.sh install-phase6.sh || true

cat > qml/pages/RolesPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var matrix: []
    readonly property var roleKeys: ["administrateur", "enseignant", "eleve", "parent", "comptable"]
    readonly property var roleLabels: ["Administrateur", "Enseignant", "Élève", "Parent", "Comptable"]

    function refresh() {
        matrix = school.permissionMatrix()
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 12

            Label { text: "Rôles et permissions"; font.pixelSize: 28; font.bold: true }
            Label {
                text: "Cochez ce que chaque rôle peut faire. Les changements sont appliqués immédiatement et enregistrés dans le journal d'audit."
                color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Droit"; font.bold: true; color: "#667085"; Layout.fillWidth: true }
                Repeater {
                    model: root.roleLabels
                    delegate: Label {
                        text: modelData; font.bold: true; color: "#667085"
                        Layout.preferredWidth: 110; horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Repeater {
                model: root.matrix
                delegate: Rectangle {
                    id: rowItem
                    property var row: modelData
                    Layout.fillWidth: true
                    implicitHeight: rowLayout.implicitHeight + 16
                    radius: 10
                    color: "white"
                    border.color: "#E5EAEE"

                    RowLayout {
                        id: rowLayout
                        anchors.fill: parent
                        anchors.margins: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label { text: rowItem.row.label; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Label { text: rowItem.row.group; color: "#667085"; font.pixelSize: 11 }
                        }

                        Repeater {
                            model: root.roleKeys
                            delegate: CheckBox {
                                Layout.preferredWidth: 110
                                checked: rowItem.row.roles[modelData] === true
                                enabled: !(modelData === "administrateur" && rowItem.row.key === "roles.manage")
                                onToggled: {
                                    school.setPermission(modelData, rowItem.row.key, checked)
                                    root.refresh()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
QML

python3 <<'PY'
import re, glob

def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

ROLES = ["administrateur", "enseignant", "eleve", "parent", "comptable"]

PERMS = [
    ("students.view", "Voir les élèves et leurs fiches", "Élèves", ["administrateur", "enseignant", "comptable"]),
    ("students.create", "Inscrire un élève", "Élèves", ["administrateur", "enseignant"]),
    ("students.edit", "Modifier une fiche élève", "Élèves", ["administrateur", "enseignant"]),
    ("students.block", "Bloquer ou débloquer un élève", "Élèves", ["administrateur", "enseignant"]),
    ("students.delete", "Supprimer un élève ou le marquer diplômé", "Élèves", ["administrateur"]),
    ("guardians.read", "Voir les parents et tuteurs", "Élèves", ["administrateur", "enseignant"]),
    ("guardians.add", "Ajouter un tuteur", "Élèves", ["administrateur", "enseignant"]),
    ("guardians.remove", "Retirer un tuteur", "Élèves", ["administrateur"]),
    ("parents.link", "Lier un compte parent à un élève", "Élèves", ["administrateur"]),
    ("teachers.manage", "Gérer les enseignants", "Personnel", ["administrateur"]),
    ("courses.manage", "Gérer les cours et ressources", "Pédagogie", ["administrateur", "enseignant"]),
    ("exams.manage", "Gérer les examens", "Pédagogie", ["administrateur", "enseignant"]),
    ("grades.edit", "Saisir les notes", "Pédagogie", ["administrateur", "enseignant"]),
    ("tardiness.record", "Enregistrer les retards", "Vie scolaire", ["administrateur", "enseignant"]),
    ("payments.create", "Enregistrer un paiement", "Finances", ["administrateur", "comptable"]),
    ("fees.student", "Définir le tarif individuel d'un élève", "Finances", ["administrateur"]),
    ("fees.tuition", "Modifier la grille tarifaire par classe", "Finances", ["administrateur", "comptable"]),
    ("invoices.generate", "Générer les factures mensuelles", "Finances", ["administrateur", "comptable"]),
    ("invoices.remind", "Lancer les relances de paiement", "Finances", ["administrateur", "comptable"]),
    ("balances.view", "Voir la vue d'ensemble des soldes", "Finances", ["administrateur", "comptable"]),
    ("accounting.write", "Saisir les écritures et les dépenses", "Comptabilité", ["administrateur", "comptable"]),
    ("accounting.export", "Exporter la comptabilité", "Comptabilité", ["administrateur", "comptable"]),
    ("communication.announcements", "Publier et supprimer des annonces", "Communication", ["administrateur"]),
    ("users.manage", "Créer des comptes, changer un rôle, réinitialiser un mot de passe", "Comptes", ["administrateur"]),
    ("users.block", "Bloquer un compte", "Comptes", ["administrateur", "enseignant", "comptable"]),
    ("users.unblock", "Débloquer un compte", "Comptes", ["administrateur", "comptable"]),
    ("periods.manage", "Gérer les périodes académiques et d'examen", "Administration", ["administrateur"]),
    ("settings.manage", "Modifier les paramètres de l'établissement", "Administration", ["administrateur"]),
    ("audit.view", "Consulter le journal d'audit", "Administration", ["administrateur"]),
    ("roles.manage", "Gérer les rôles et les permissions", "Administration", ["administrateur"]),
]

FN2KEY = {
    "addStudent": "students.create", "updateStudent": "students.edit",
    "deleteStudent": "students.delete", "graduateStudent": "students.delete",
    "blockStudent": "students.block", "canViewStudent": "students.view",
    "addTeacher": "teachers.manage", "updateTeacher": "teachers.manage", "deleteTeacher": "teachers.manage",
    "addCourse": "courses.manage", "updateCourse": "courses.manage", "deleteCourse": "courses.manage",
    "addResource": "courses.manage", "deleteResource": "courses.manage",
    "addExam": "exams.manage", "updateExam": "exams.manage", "deleteExam": "exams.manage",
    "saveGrade": "grades.edit", "addTardiness": "tardiness.record",
    "guardians": "guardians.read", "addGuardian": "guardians.add", "removeGuardian": "guardians.remove",
    "parentLinks": "parents.link", "linkParentByEmail": "parents.link", "unlinkParent": "parents.link",
    "addPayment": "payments.create", "setStudentFee": "fees.student", "setClassTuition": "fees.tuition",
    "generateMonthlyInvoices": "invoices.generate", "processPaymentReminders": "invoices.remind",
    "balanceOverview": "balances.view", "addAccount": "accounting.write", "addExpense": "accounting.write",
    "exportAccountingCsv": "accounting.export",
    "createUser": "users.manage", "updateUserRole": "users.manage", "resetPassword": "users.manage",
    "blockUser": "users.block", "unblockUser": "users.unblock",
    "addAnnouncement": "communication.announcements", "deleteAnnouncement": "communication.announcements",
    "addExamPeriod": "periods.manage", "toggleExamPeriod": "periods.manage",
    "addAcademicPeriod": "periods.manage", "setActiveAcademicPeriod": "periods.manage",
    "setSetting": "settings.manage", "auditLogs": "audit.view",
}

cpp = 'src/core/SchoolApp.cpp'
lines = open(cpp, encoding='utf-8').read().split('\n')
current = None
replaced = 0
fn_re = re.compile(r'^(bool|QVariantList|QVariantMap|QString|QStringList|void|int)\s+SchoolApp::(\w+)\(')
call_re = re.compile(r'allowed\(\{[^}]*\}\)')
for i, line in enumerate(lines):
    m = fn_re.match(line)
    if m:
        current = m.group(2)
    if 'allowed(const QStringList' in line:
        continue
    if call_re.search(line):
        if current not in FN2KEY:
            raise SystemExit("Fonction non mappée : " + str(current))
        lines[i] = call_re.sub('can("%s")' % FN2KEY[current], line)
        replaced += 1
open(cpp, 'w', encoding='utf-8').write('\n'.join(lines))
print("vérifications converties :", replaced)

hd = 'src/core/SchoolApp.h'
edit(hd, '    Q_INVOKABLE QVariantList auditLogs(int limit) const;\n', '''    Q_INVOKABLE QVariantList auditLogs(int limit) const;

    Q_INVOKABLE bool can(const QString &permission) const;
    Q_INVOKABLE QVariantList permissionMatrix() const;
    Q_INVOKABLE bool setPermission(const QString &role, const QString &permission, bool allowedValue);
''')

db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS permissions_catalog(
            key TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            grp TEXT NOT NULL
        ))",

        R"(CREATE TABLE IF NOT EXISTS role_permissions(
            role TEXT NOT NULL,
            permission TEXT NOT NULL,
            allowed INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(role, permission)
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')

seed_lines = []
for key, label, group, roles in PERMS:
    safe_label = label.replace("'", "''")
    seed_lines.append('    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES(\'%s\',\'%s\',\'%s\')")) return false;' % (key, safe_label, group))
    vals = ",".join("('%s','%s',%d)" % (r, key, 1 if r in roles else 0) for r in ROLES)
    seed_lines.append('    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES %s")) return false;' % vals)
seed_block = "\n".join(seed_lines) + "\n"
edit(db, 'bool Database::seed()\n{\n', 'bool Database::seed()\n{\n' + seed_block + '\n')

s = open(cpp, encoding='utf-8').read()
s += '''
bool SchoolApp::can(const QString &permission) const
{
    if (m_userId <= 0) return false;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT allowed FROM role_permissions WHERE role=? AND permission=?");
    q.addBindValue(m_role);
    q.addBindValue(permission);
    return q.exec() && q.next() && q.value(0).toInt() == 1;
}

QVariantList SchoolApp::permissionMatrix() const
{
    QVariantList out;
    if (!can("roles.manage")) return out;
    QSqlQuery cat(m_db.db());
    if (!cat.exec("SELECT key,label,grp FROM permissions_catalog ORDER BY grp,label")) return out;
    while (cat.next()) {
        QVariantMap row;
        row["key"] = cat.value(0).toString();
        row["label"] = cat.value(1).toString();
        row["group"] = cat.value(2).toString();
        QVariantMap roles;
        QSqlQuery r(m_db.db());
        r.prepare("SELECT role,allowed FROM role_permissions WHERE permission=?");
        r.addBindValue(row["key"].toString());
        if (r.exec()) {
            while (r.next()) roles[r.value(0).toString()] = r.value(1).toInt() == 1;
        }
        row["roles"] = roles;
        out << row;
    }
    return out;
}

bool SchoolApp::setPermission(const QString &role, const QString &permission, bool allowedValue)
{
    if (!can("roles.manage")) return false;
    if (!roles().contains(role)) {
        emit errorOccurred(QStringLiteral("Rôle inconnu."));
        return false;
    }
    if (role == QLatin1String("administrateur") && permission == QLatin1String("roles.manage") && !allowedValue) {
        emit errorOccurred(QStringLiteral("L'administrateur doit toujours pouvoir gérer les rôles et les permissions."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE role_permissions SET allowed=? WHERE role=? AND permission=?");
    q.addBindValue(allowedValue ? 1 : 0);
    q.addBindValue(role);
    q.addBindValue(permission);
    if (!q.exec() || q.numRowsAffected() != 1) {
        emit errorOccurred(QStringLiteral("Droit inconnu."));
        return false;
    }
    audit("update", "permission", 0, role + " " + permission + (allowedValue ? " = oui" : " = non"));
    emit dataChanged();
    return true;
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sb = 'qml/components/Sidebar.qml'
s = open(sb, encoding='utf-8').read()
if '["fees", "Frais et soldes", "🏷"]' in s:
    anchor = '["fees", "Frais et soldes", "🏷"]'
else:
    anchor = '["audit", "Journal d\'audit", "📜"]'
edit(sb, anchor, anchor + ',\n                ["roles", "Rôles et permissions", "🛡"]')

mq = 'qml/Main.qml'
s = open(mq, encoding='utf-8').read()
if '"fees":15}' in s:
    edit(mq, '"fees":15}', '"fees":15,"roles":16}')
else:
    edit(mq, '"audit":14}', '"audit":14,"roles":16}')
if 'FeesPage {}\n' in s:
    edit(mq, 'FeesPage {}\n', 'FeesPage {}\n                        RolesPage {}\n')
else:
    edit(mq, 'AuditPage {}\n', 'AuditPage {}\n                        RolesPage {}\n')

cm = 'CMakeLists.txt'
s = open(cm, encoding='utf-8').read()
if '        qml/pages/FeesPage.qml\n' in s:
    edit(cm, '        qml/pages/FeesPage.qml\n', '        qml/pages/FeesPage.qml\n        qml/pages/RolesPage.qml\n')
else:
    edit(cm, '        qml/pages/AuditPage.qml\n', '        qml/pages/AuditPage.qml\n        qml/pages/RolesPage.qml\n')
print("phase 6 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: rôles et permissions configurables (matrice des droits, page Rôles et permissions)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-roles-permissions."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-roles-permissions"
