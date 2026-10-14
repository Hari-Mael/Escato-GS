#!/usr/bin/env bash
set -euo pipefail

if [ ! -f CMakeLists.txt ] || [ ! -d qml ]; then
    echo "Erreur : lance ce script à la racine du dépôt Escato-GS"
    exit 1
fi

git checkout main
git pull --ff-only
git checkout -B feat/escato-gs-rapports-email main
git rm -q --ignore-unmatch install-phase*.sh || true

cat > qml/pages/EmailPage.qml <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var cfg: ({})
    property var logRows: []
    property bool canConfig: false
    property bool canSend: false

    function refresh() {
        canConfig = school.can("email.config")
        canSend = school.can("email.send")
        cfg = school.smtpSettings()
        logRows = school.emailLog(200)
        if (cfg.host !== undefined) {
            hostField.text = cfg.host || ""
            portField.text = String(cfg.port || 587)
            userField.text = cfg.user || ""
            fromField.text = cfg.from || ""
            timeField.text = cfg.scheduleTime || "08:00"
            schedCheck.checked = !!cfg.scheduleEnabled
            securityBox.currentIndex = Math.max(0, ["starttls", "ssl", "none"].indexOf(cfg.security || "starttls"))
        }
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 18

            Label { text: "Rapports par e-mail"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                visible: root.canConfig
                implicitHeight: smtpColumn.implicitHeight + 40
                ColumnLayout {
                    id: smtpColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Serveur d'envoi (SMTP)"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Le mot de passe n'est jamais enregistré : saisissez-le à chaque session. Pour Gmail, utilisez un mot de passe d'application."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: hostField; placeholderText: "Serveur (ex. smtp.gmail.com)"; Layout.fillWidth: true }
                        AppTextField { id: portField; placeholderText: "Port"; Layout.preferredWidth: 90; inputMethodHints: Qt.ImhDigitsOnly }
                        ComboBox { id: securityBox; Layout.preferredWidth: 180; model: ["STARTTLS", "SSL", "Sans chiffrement"] }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: userField; placeholderText: "Identifiant (adresse e-mail)"; Layout.fillWidth: true }
                        AppTextField { id: fromField; placeholderText: "Adresse expéditrice"; Layout.fillWidth: true }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: passField; placeholderText: "Mot de passe (session uniquement)"; echoMode: TextInput.Password; Layout.fillWidth: true }
                        AppButton { text: "Mémoriser pour cette session"; onClicked: { school.setSmtpPassword(passField.text); passField.text = "" } }
                    }
                    AppButton {
                        text: "Enregistrer le serveur"; highlighted: true
                        onClicked: school.saveSmtpSettings({host: hostField.text, port: parseInt(portField.text) || 587, user: userField.text,
                                                            from: fromField.text, security: ["starttls", "ssl", "none"][securityBox.currentIndex]})
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                visible: root.canSend
                implicitHeight: sendColumn.implicitHeight + 40
                ColumnLayout {
                    id: sendColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Envois"; font.pixelSize: 18; font.bold: true }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: testTo; placeholderText: "Adresse de test"; Layout.fillWidth: true }
                        AppButton { text: "Envoyer un test"; visible: root.canConfig; onClicked: school.sendTestEmail(testTo.text) }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppButton { text: "Relancer les parents (impayés)"; highlighted: true; onClicked: school.sendOverdueReminders() }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        CheckBox { id: schedCheck; text: "Relances automatiques chaque jour à" }
                        AppTextField { id: timeField; Layout.preferredWidth: 90; placeholderText: "HH:mm" }
                        AppButton {
                            text: "Enregistrer la planification"; visible: root.canConfig
                            onClicked: school.saveEmailSchedule(schedCheck.checked, timeField.text)
                        }
                    }
                    Label {
                        text: "La planification ne fonctionne que si l'application est ouverte et qu'une session est active à l'heure prévue."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                visible: root.canSend
                implicitHeight: logColumn.implicitHeight + 40
                ColumnLayout {
                    id: logColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 6
                    Label { text: "Historique des envois"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.logRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.createdAt; Layout.preferredWidth: 150; color: "#667085" }
                            Label { text: modelData.recipient; Layout.preferredWidth: 220; elide: Text.ElideRight }
                            Label { text: modelData.subject; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: modelData.status; font.bold: true; color: modelData.status === "envoyé" ? "#0F9D8F" : "#C62828" }
                        }
                    }
                }
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

ROLES = ["administrateur", "enseignant", "eleve", "parent", "comptable"]
PERMS = [
    ("email.config", "Configurer le serveur d'envoi et la planification", "Communication", ["administrateur"]),
    ("email.send", "Envoyer des e-mails (relances, situations, tests)", "Communication", ["administrateur", "comptable"]),
]
db = 'src/core/Database.cpp'
edit(db, '        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(\n', '''        R"(CREATE TABLE IF NOT EXISTS email_log(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recipient TEXT NOT NULL,
            subject TEXT NOT NULL,
            status TEXT NOT NULL,
            error TEXT,
            user_id INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
''')
seed = []
for key, label, group, roles in PERMS:
    seed.append('    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES(\'%s\',\'%s\',\'%s\')")) return false;' % (key, label.replace("'", "''"), group))
    vals = ",".join("('%s','%s',%d)" % (r, key, 1 if r in roles else 0) for r in ROLES)
    seed.append('    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES %s")) return false;' % vals)
edit(db, 'bool Database::seed()\n{\n', 'bool Database::seed()\n{\n' + "\n".join(seed) + "\n\n")

hd = 'src/core/SchoolApp.h'
edit(hd, 'class SchoolApp : public QObject', '#include <QTimer>\n\nclass SchoolApp : public QObject')
edit(hd, '    Q_INVOKABLE QVariantList auditLogs(int limit) const;\n', '''    Q_INVOKABLE QVariantList auditLogs(int limit) const;

    Q_INVOKABLE QVariantMap smtpSettings() const;
    Q_INVOKABLE bool saveSmtpSettings(const QVariantMap &v);
    Q_INVOKABLE void setSmtpPassword(const QString &password);
    Q_INVOKABLE bool saveEmailSchedule(bool enabled, const QString &time);
    Q_INVOKABLE bool sendTestEmail(const QString &to);
    Q_INVOKABLE int sendOverdueReminders();
    Q_INVOKABLE bool sendStudentSituation(int studentId);
    Q_INVOKABLE QVariantList emailLog(int limit) const;
''')
edit(hd, '    int m_userId = 0;\n', '    int m_userId = 0;\n    QString m_smtpPassword;\n    QTimer *m_emailTimer = nullptr;\n')
edit(hd, 'private:\n', 'private slots:\n    void runScheduledEmails();\n\nprivate:\n    bool sendMail(const QString &to, const QString &subject, const QString &body, QString *error) const;\n    void logEmail(const QString &to, const QString &subject, bool ok, const QString &error);\n')

cpp = 'src/core/SchoolApp.cpp'
edit(cpp, '#include <QStringConverter>\n', '#include <QStringConverter>\n#include <QSslSocket>\n#include <QTimer>\n#include <QTime>\n#include <QSet>\n')
edit(cpp, 'SchoolApp::SchoolApp(QObject *parent) : QObject(parent)\n{\n', '''SchoolApp::SchoolApp(QObject *parent) : QObject(parent)
{
    m_emailTimer = new QTimer(this);
    connect(m_emailTimer, &QTimer::timeout, this, &SchoolApp::runScheduledEmails);
    m_emailTimer->start(60000);
''')
edit(cpp, '    m_userId = 0; m_userName.clear(); m_role.clear();\n', '    m_userId = 0; m_userName.clear(); m_role.clear(); m_smtpPassword.clear();\n')

s = open(cpp, encoding='utf-8').read()
s += '''
namespace {
bool smtpExpect(QSslSocket &s, const QString &command, int expected, QString &error)
{
    if (!command.isEmpty()) {
        const QByteArray bytes = (command + "\\r\\n").toUtf8();
        if (s.write(bytes) != bytes.size() || !s.waitForBytesWritten(15000)) { error = QStringLiteral("envoi interrompu"); return false; }
    }
    QString text;
    for (;;) {
        if (!s.canReadLine() && !s.waitForReadyRead(15000)) { error = QStringLiteral("pas de réponse du serveur"); return false; }
        while (s.canReadLine()) {
            const QString line = QString::fromUtf8(s.readLine()).trimmed();
            text += line + "\\n";
            if (line.size() >= 3 && (line.size() == 3 || line[3] == ' ')) {
                const int code = line.left(3).toInt();
                if (code != expected) { error = QStringLiteral("réponse serveur : ") + line; return false; }
                return true;
            }
        }
    }
}
}

bool SchoolApp::sendMail(const QString &to, const QString &subject, const QString &body, QString *error) const
{
    QString err;
    const QString host = setting("smtp_host").trimmed();
    const int port = setting("smtp_port").isEmpty() ? 587 : setting("smtp_port").toInt();
    const QString user = setting("smtp_user").trimmed();
    const QString from = setting("smtp_from").trimmed();
    const QString security = setting("smtp_security").isEmpty() ? QStringLiteral("starttls") : setting("smtp_security");
    if (host.isEmpty() || from.isEmpty() || to.trimmed().isEmpty()) {
        if (error) *error = QStringLiteral("serveur, adresse expéditrice ou destinataire manquant");
        return false;
    }
    QSslSocket s;
    if (security == QLatin1String("ssl")) {
        s.connectToHostEncrypted(host, port);
        if (!s.waitForEncrypted(15000)) { if (error) *error = QStringLiteral("connexion SSL impossible"); return false; }
    } else {
        s.connectToHost(host, port);
        if (!s.waitForConnected(15000)) { if (error) *error = QStringLiteral("connexion impossible"); return false; }
    }
    bool ok = smtpExpect(s, QString(), 220, err)
        && smtpExpect(s, QStringLiteral("EHLO escato.local"), 250, err);
    if (ok && security == QLatin1String("starttls")) {
        ok = smtpExpect(s, QStringLiteral("STARTTLS"), 220, err);
        if (ok) { s.startClientEncryption(); ok = s.waitForEncrypted(15000); if (!ok) err = QStringLiteral("STARTTLS impossible"); }
        if (ok) ok = smtpExpect(s, QStringLiteral("EHLO escato.local"), 250, err);
    }
    if (ok && !user.isEmpty()) {
        ok = smtpExpect(s, QStringLiteral("AUTH LOGIN"), 334, err)
            && smtpExpect(s, QString::fromLatin1(user.toUtf8().toBase64()), 334, err)
            && smtpExpect(s, QString::fromLatin1(m_smtpPassword.toUtf8().toBase64()), 235, err);
    }
    if (ok) {
        const QString mime = "=?UTF-8?B?" + QString::fromLatin1(subject.toUtf8().toBase64()) + "?=";
        QStringList headers;
        headers << "From: " + from << "To: " + to.trimmed() << "Subject: " + mime
                << "Date: " + QDateTime::currentDateTime().toString(Qt::RFC2822Date)
                << "MIME-Version: 1.0" << "Content-Type: text/plain; charset=UTF-8" << "Content-Transfer-Encoding: 8bit";
        QStringList bodyLines;
        for (const QString &line : body.split('\\n')) bodyLines << (line.startsWith('.') ? "." + line : line);
        const QByteArray data = (headers.join("\\r\\n") + "\\r\\n\\r\\n" + bodyLines.join("\\r\\n") + "\\r\\n.").toUtf8();
        ok = smtpExpect(s, QStringLiteral("MAIL FROM:<%1>").arg(from), 250, err)
            && smtpExpect(s, QStringLiteral("RCPT TO:<%1>").arg(to.trimmed()), 250, err)
            && smtpExpect(s, QStringLiteral("DATA"), 354, err);
        if (ok) {
            const QByteArray payload = data + "\\r\\n";
            s.write(payload);
            ok = s.waitForBytesWritten(15000) && smtpExpect(s, QString(), 250, err);
        }
    }
    if (s.state() == QAbstractSocket::ConnectedState) smtpExpect(s, QStringLiteral("QUIT"), 221, err);
    s.disconnectFromHost();
    if (!ok && error) *error = err;
    return ok;
}

void SchoolApp::logEmail(const QString &to, const QString &subject, bool ok, const QString &error)
{
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO email_log(recipient,subject,status,error,user_id) VALUES(?,?,?,?,?)");
    q.addBindValue(to);
    q.addBindValue(subject);
    q.addBindValue(ok ? QStringLiteral("envoyé") : QStringLiteral("échec"));
    q.addBindValue(error);
    q.addBindValue(m_userId > 0 ? QVariant(m_userId) : QVariant());
    q.exec();
}

QVariantMap SchoolApp::smtpSettings() const
{
    QVariantMap out;
    if (!can("email.config")) return out;
    out["host"] = setting("smtp_host");
    out["port"] = setting("smtp_port").isEmpty() ? 587 : setting("smtp_port").toInt();
    out["user"] = setting("smtp_user");
    out["from"] = setting("smtp_from");
    out["security"] = setting("smtp_security").isEmpty() ? QStringLiteral("starttls") : setting("smtp_security");
    out["scheduleEnabled"] = setting("email_schedule_enabled") == QLatin1String("1");
    out["scheduleTime"] = setting("email_schedule_time").isEmpty() ? QStringLiteral("08:00") : setting("email_schedule_time");
    out["passwordSet"] = !m_smtpPassword.isEmpty();
    return out;
}

bool SchoolApp::saveSmtpSettings(const QVariantMap &v)
{
    if (!can("email.config")) return false;
    const QString host = v.value("host").toString().trimmed();
    const QString security = v.value("security").toString();
    if (host.isEmpty() || !QStringList({"starttls", "ssl", "none"}).contains(security)) {
        emit errorOccurred(QStringLiteral("Serveur et mode de chiffrement (starttls, ssl ou none) requis."));
        return false;
    }
    setSetting("smtp_host", host);
    setSetting("smtp_port", QString::number(v.value("port").toInt() > 0 ? v.value("port").toInt() : 587));
    setSetting("smtp_user", v.value("user").toString().trimmed());
    setSetting("smtp_from", v.value("from").toString().trimmed());
    setSetting("smtp_security", security);
    return true;
}

void SchoolApp::setSmtpPassword(const QString &password)
{
    if (!can("email.config")) return;
    m_smtpPassword = password;
    emit dataChanged();
}

bool SchoolApp::saveEmailSchedule(bool enabled, const QString &time)
{
    if (!can("email.config")) return false;
    if (!QTime::fromString(time.trimmed(), "HH:mm").isValid()) {
        emit errorOccurred(QStringLiteral("Heure au format HH:mm requise."));
        return false;
    }
    setSetting("email_schedule_enabled", enabled ? "1" : "0");
    setSetting("email_schedule_time", QTime::fromString(time.trimmed(), "HH:mm").toString("HH:mm"));
    return true;
}

bool SchoolApp::sendTestEmail(const QString &to)
{
    if (!can("email.config")) return false;
    QString err;
    const bool ok = sendMail(to, QStringLiteral("Test ESCATO GS"), QStringLiteral("Ce message confirme que la configuration e-mail fonctionne."), &err);
    logEmail(to, QStringLiteral("Test ESCATO GS"), ok, err);
    if (!ok) emit errorOccurred(QStringLiteral("Envoi impossible : ") + err);
    emit dataChanged();
    return ok;
}

int SchoolApp::sendOverdueReminders()
{
    if (!can("email.send")) return 0;
    const QString school_name = setting("school_name").isEmpty() ? QStringLiteral("l'établissement") : setting("school_name");
    const QString today = QDate::currentDate().toString("dd/MM/yyyy");
    int sent = 0, failed = 0;
    for (const QVariant &v : overdueByStudent(QString())) {
        const QVariantMap m = v.toMap();
        QSqlQuery q(m_db.db());
        q.prepare("SELECT COALESCE(parent_email,'') FROM students WHERE id=?");
        q.addBindValue(m["studentId"].toInt());
        if (!q.exec() || !q.next()) continue;
        const QString to = q.value(0).toString().trimmed();
        if (to.isEmpty()) continue;
        const QString subject = QStringLiteral("Rappel de paiement - %1").arg(m["name"].toString());
        const QString body = QStringLiteral("Bonjour,\\n\\nNous vous informons que le solde restant dû pour %1 est de %2 à la date du %3.\\n\\nMerci de bien vouloir régulariser la situation auprès de l'administration.\\n\\n%4")
                                .arg(m["name"].toString(), QLocale(QLocale::French).toString(m["total"].toDouble(), 'f', 0) + QStringLiteral(" Ar"), today, school_name);
        QString err;
        const bool ok = sendMail(to, subject, body, &err);
        logEmail(to, subject, ok, err);
        ok ? ++sent : ++failed;
    }
    emit dataChanged();
    if (failed > 0) emit errorOccurred(QStringLiteral("%1 relance(s) envoyée(s), %2 échec(s) : voir l'historique.").arg(sent).arg(failed));
    return sent;
}

bool SchoolApp::sendStudentSituation(int studentId)
{
    if (!can("email.send")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE(parent_email,''), last_name || ' ' || first_name FROM students WHERE id=? AND deleted_at IS NULL");
    q.addBindValue(studentId);
    if (!q.exec() || !q.next()) return false;
    const QString to = q.value(0).toString().trimmed();
    const QString name = q.value(1).toString();
    if (to.isEmpty()) { emit errorOccurred(QStringLiteral("Cet élève n'a pas d'adresse e-mail de parent.")); return false; }
    double billed = 0;
    for (const QVariant &v : studentInvoices(studentId)) billed += v.toMap()["amount"].toDouble();
    double paid = 0;
    for (const QVariant &v : payments(studentId)) paid += v.toMap()["amount"].toDouble();
    const QString subject = QStringLiteral("Situation financière - %1").arg(name);
    const QString body = QStringLiteral("Bonjour,\\n\\nSituation financière de %1 :\\n- montant facturé : %2\\n- montant encaissé : %3\\n- solde : %4\\n\\nCordialement.")
                            .arg(name,
                                 QLocale(QLocale::French).toString(billed, 'f', 0) + QStringLiteral(" Ar"),
                                 QLocale(QLocale::French).toString(paid, 'f', 0) + QStringLiteral(" Ar"),
                                 QLocale(QLocale::French).toString(billed - paid, 'f', 0) + QStringLiteral(" Ar"));
    QString err;
    const bool ok = sendMail(to, subject, body, &err);
    logEmail(to, subject, ok, err);
    if (!ok) emit errorOccurred(QStringLiteral("Envoi impossible : ") + err);
    emit dataChanged();
    return ok;
}

QVariantList SchoolApp::emailLog(int limit) const
{
    QVariantList out;
    if (!can("email.send")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT created_at, recipient, subject, status FROM email_log ORDER BY id DESC LIMIT ?");
    q.addBindValue(limit > 0 ? limit : 200);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["createdAt"] = q.value(0).toString();
        m["recipient"] = q.value(1).toString();
        m["subject"] = q.value(2).toString();
        m["status"] = q.value(3).toString();
        out << m;
    }
    return out;
}

void SchoolApp::runScheduledEmails()
{
    if (m_userId <= 0) return;
    if (setting("email_schedule_enabled") != QLatin1String("1")) return;
    const QString nowHm = QTime::currentTime().toString("HH:mm");
    if (nowHm != (setting("email_schedule_time").isEmpty() ? QStringLiteral("08:00") : setting("email_schedule_time"))) return;
    const QString today = QDate::currentDate().toString("yyyy-MM-dd");
    if (setting("email_last_run") == today) return;
    setSetting("email_last_run", today);
    sendOverdueReminders();
}
'''
open(cpp, 'w', encoding='utf-8').write(s)

sb = 'qml/components/Sidebar.qml'
edit(sb, '                ["import", "Importation des données", "📥"],\n',
     '                ["import", "Importation des données", "📥"],\n                ["email", "Rapports par e-mail", "✉"],\n')
mq = 'qml/Main.qml'
edit(mq, '"import":25}', '"import":25,"email":26}')
edit(mq, '                        ImportPage {}\n', '                        ImportPage {}\n                        EmailPage {}\n')
cm = 'CMakeLists.txt'
edit(cm, '        qml/pages/ImportPage.qml\n', '        qml/pages/ImportPage.qml\n        qml/pages/EmailPage.qml\n')
print("phase 16 appliquée")
PY

git add -A
git -c user.name="$(git config user.name || echo dev)" -c user.email="$(git config user.email || echo dev@local)" \
    commit -m "feat: rapports par e-mail (serveur SMTP, relances aux parents, situation d'élève, historique, planification)"

echo ""
echo "Commit créé sur la branche feat/escato-gs-rapports-email."
echo "Pour envoyer sur GitHub : git push -u origin feat/escato-gs-rapports-email"
