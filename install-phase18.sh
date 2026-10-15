#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-securite-controles main
git rm -q --ignore-unmatch install-phase*.sh || true

python3 <<'PY'
import re

def edit(path, old, new, count=1):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == count, (path, s.count(old), old[:70])
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

hd = 'src/core/SchoolApp.h'
edit(hd, '    bool canViewStudent(int studentId) const;\n', '''    bool canViewStudent(int studentId) const;
    bool financeVisible(int studentId) const;

public:
    bool isStudentVisible(int studentId) const { return canViewStudent(studentId); }
    bool isFinanceVisible(int studentId) const { return financeVisible(studentId); }
    bool isPaymentVisible(int paymentId) const;
    bool hasPermission(const QString &permission) const { return can(permission); }

private:
''')

cpp = 'src/core/SchoolApp.cpp'
s = open(cpp, encoding='utf-8').read()

def guard(sname, cond, default, param):
    global s
    pat = re.compile(r'(\n(?:bool|QVariantList|QVariantMap|QString)\s+SchoolApp::' + sname + r'\([^)]*\)[^{]*\{\n)')
    m = pat.search(s)
    assert m, sname
    c = cond.replace('PARAM', param)
    s = s[:m.end()] + '    if (!(' + c + ')) return ' + default + ';\n' + s[m.end():]

GUARD_LIST = '(can("students.view"))'
GUARD_FIN = '(can("balances.view"))'
GUARD_ACC = '(can("finance.reports") || can("accounting.write"))'
GUARD_STATS = '(can("students.view") || can("balances.view"))'
GUARD_GRADES = '(can("grades.edit") || can("deliberations.view"))'
for name, cond, default in [
    ('students', GUARD_LIST, 'QVariantList()'),
    ('invoices', GUARD_FIN, 'QVariantList()'),
    ('journal', GUARD_ACC, 'QVariantList()'),
    ('generalLedger', GUARD_ACC, 'QVariantList()'),
    ('trialBalance', GUARD_ACC, 'QVariantList()'),
    ('chartOfAccounts', GUARD_ACC, 'QVariantList()'),
    ('expenses', GUARD_ACC, 'QVariantList()'),
    ('accountingDashboard', GUARD_ACC, 'QVariantMap()'),
    ('monthlyStats', GUARD_STATS, 'QVariantMap()'),
    ('dashboard', GUARD_STATS, 'QVariantList()'),
    ('grades', GUARD_GRADES, 'QVariantList()'),
    ('exams', GUARD_GRADES, 'QVariantList()'),
    ('tardiness', '(can("attendance.record"))', 'QVariantList()'),
]:
    guard(name, cond, default, 'x')

for name in ['student', 'payments', 'studentInvoices', 'bulletin']:
    pat = re.compile(r'\n(?:QVariantMap|QVariantList)\s+SchoolApp::' + name + r'\(int (\w+)')
    m = pat.search(s)
    assert m, name
    param = m.group(1)
    if name in ('payments', 'studentInvoices'):
        cond = 'financeVisible(%s)' % param
    else:
        cond = 'canViewStudent(%s)' % param
    default = 'QVariantMap()' if name in ('student', 'bulletin') else 'QVariantList()'
    guard(name, cond, default, param)

m = re.search(r'\nbool SchoolApp::unblockStudent\(int (\w+)\)', s)
assert m
guard('unblockStudent', '(can("students.block"))', 'false', m.group(1))

m = re.search(r'\nQString SchoolApp::setting\(const QString &(\w+)\) const\n\{\n', s)
assert m
key = m.group(1)
s = s[:m.end()] + '    if (%s.startsWith("smtp_") && !can("email.config")) return QString();\n' % key + s[m.end():]

m = re.search(r'\nQVariantList SchoolApp::users\(const QString &role\) const\n\{\n', s)
assert m
s = s[:m.end()] + '    if (m_userId <= 0) return QVariantList();\n' + s[m.end():]
old_loop = 'for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);out<<m;}return out;'
new_loop = ('for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);'
            'if(!can("users.manage")){m.remove("email");m.remove("status");m.remove("blockedReason");m.remove("blockedCategory");m.remove("requiresPasswordReset");}'
            'out<<m;}return out;')
start = s.index('QVariantList SchoolApp::users(const QString &role) const')
end = s.index('\n}\n', start)
body = s[start:end]
assert body.count(old_loop) == 1, body.count(old_loop)
s = s[:start] + body.replace(old_loop, new_loop) + s[end:]

s += '''
bool SchoolApp::financeVisible(int studentId) const
{
    return can("balances.view") || (canViewStudent(studentId) && !can("students.view"));
}

bool SchoolApp::isPaymentVisible(int paymentId) const
{
    QSqlQuery q(m_db.db());
    q.prepare("SELECT student_id FROM payments WHERE id=?");
    q.addBindValue(paymentId);
    return q.exec() && q.next() && financeVisible(q.value(0).toInt());
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

pmc = 'src/core/PrintManager.cpp'
s = open(pmc, encoding='utf-8').read()
GUARDS = {
    'printStudentList': 'if (!m_school || !m_school->hasPermission("students.view")) return false;',
    'exportStudentsPdf': 'if (!m_school || !m_school->hasPermission("students.view")) return false;',
    'printTeacherList': 'if (!m_school || !(m_school->hasPermission("teachers.manage") || m_school->hasPermission("students.view"))) return false;',
    'printStudentCertificate': 'if (!m_school || !m_school->isStudentVisible(studentId)) return false;',
    'exportStudentCertificatePdf': 'if (!m_school || !m_school->isStudentVisible(studentId)) return false;',
    'printStudentCard': 'if (!m_school || !m_school->isStudentVisible(studentId)) return false;',
    'exportStudentCardPdf': 'if (!m_school || !m_school->isStudentVisible(studentId)) return false;',
    'printAttestation': 'if (!m_school || !m_school->isStudentVisible(studentId)) return false;',
    'exportAttestationPdf': 'if (!m_school || !m_school->isStudentVisible(studentId)) return false;',
    'printBulletin': 'if (!m_school || !m_school->isStudentVisible(studentId)) return false;',
    'exportBulletinPdf': 'if (!m_school || !m_school->isStudentVisible(studentId)) return false;',
    'printPaymentRequest': 'if (!m_school || !m_school->isFinanceVisible(studentId)) return false;',
    'exportPaymentRequestPdf': 'if (!m_school || !m_school->isFinanceVisible(studentId)) return false;',
    'printReceipt': 'if (!m_school || !m_school->isPaymentVisible(paymentId)) return false;',
    'exportReceiptPdf': 'if (!m_school || !m_school->isPaymentVisible(paymentId)) return false;',
}
for name, line in GUARDS.items():
    pat = re.compile(r'(bool PrintManager::' + name + r'\([^)]*\)\n\{\n)')
    m = pat.search(s)
    assert m, name
    s = s[:m.end()] + '    ' + line + '\n' + s[m.end():]
open(pmc, 'w', encoding='utf-8').write(s)
print("phase 18 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "security: contrôle des droits sur les lectures sensibles, impressions et paramètres SMTP, liste des utilisateurs limitée"

echo ""
echo "Commit créé sur la branche feat/escato-gs-securite-controles."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-securite-controles"
