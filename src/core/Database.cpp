#include "Database.h"
#include <QStandardPaths>
#include <QDir>
#include <QSqlQuery>
#include <QSqlError>
#include <QCryptographicHash>
#include <QPasswordDigestor>
#include <QRandomGenerator>
#include <QDebug>

namespace {
constexpr int kPbkdf2Iterations = 210000;
constexpr int kSaltBytes = 16;
constexpr int kKeyBytes = 32;

QByteArray randomBytes(int n)
{
    QByteArray b(n, Qt::Uninitialized);
    for (int i = 0; i < n; ++i)
        b[i] = static_cast<char>(QRandomGenerator::system()->generate() & 0xFF);
    return b;
}

QByteArray pbkdf2(const QString &password, const QByteArray &salt, int iterations)
{
    return QPasswordDigestor::deriveKeyPbkdf2(QCryptographicHash::Sha256, password.toUtf8(), salt, iterations, kKeyBytes);
}

bool constantTimeEquals(const QByteArray &a, const QByteArray &b)
{
    if (a.size() != b.size()) return false;
    unsigned char diff = 0;
    for (int i = 0; i < a.size(); ++i)
        diff |= static_cast<unsigned char>(a[i]) ^ static_cast<unsigned char>(b[i]);
    return diff == 0;
}

// Ancien format (versions < ce correctif) : SHA-256 sans sel. Utilisé uniquement par
// migrate() pour détecter et retirer l'admin par défaut historique "admin123".
QString legacyHashPassword(const QString &s)
{
    return QString(QCryptographicHash::hash(s.toUtf8(), QCryptographicHash::Sha256).toHex());
}
}

QString Database::hashPassword(const QString &password)
{
    const QByteArray salt = randomBytes(kSaltBytes);
    const QByteArray key = pbkdf2(password, salt, kPbkdf2Iterations);
    return QStringLiteral("pbkdf2$%1$%2$%3").arg(kPbkdf2Iterations).arg(QString::fromLatin1(salt.toHex()), QString::fromLatin1(key.toHex()));
}

bool Database::verifyPassword(const QString &password, const QString &stored)
{
    if (stored.startsWith(QStringLiteral("pbkdf2$"))) {
        const QStringList p = stored.split(QLatin1Char('$'));
        if (p.size() != 4) return false;
        bool ok = false;
        const int iterations = p[1].toInt(&ok);
        if (!ok || iterations <= 0) return false;
        const QByteArray salt = QByteArray::fromHex(p[2].toLatin1());
        const QByteArray expected = QByteArray::fromHex(p[3].toLatin1());
        return constantTimeEquals(pbkdf2(password, salt, iterations), expected);
    }
    // Compat ascendante : anciens hash SHA-256 non salés, remplacés au prochain login réussi.
    const QByteArray legacy = QCryptographicHash::hash(password.toUtf8(), QCryptographicHash::Sha256).toHex();
    return constantTimeEquals(legacy, stored.toLatin1());
}

bool Database::needsRehash(const QString &stored)
{
    return !stored.startsWith(QStringLiteral("pbkdf2$%1$").arg(kPbkdf2Iterations));
}

Database::Database(QObject *parent) : QObject(parent)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    m_db = QSqlDatabase::addDatabase("QSQLITE");
    m_db.setDatabaseName(dir + "/escato.sqlite");
}

bool Database::open()
{
    if (!m_db.open()) {
        qWarning() << m_db.lastError().text();
        return false;
    }
    exec("PRAGMA foreign_keys = ON");
    exec("PRAGMA journal_mode = WAL");
    exec("PRAGMA busy_timeout = 5000");
    return createSchema() && migrate() && seed();
}

QString Database::lastError() const { return m_db.lastError().text(); }

bool Database::exec(const QString &sql)
{
    QSqlQuery q(m_db);
    if (!q.exec(sql)) {
        qWarning() << q.lastError().text() << sql;
        return false;
    }
    return true;
}

bool Database::createSchema()
{
    const QStringList schema = {
        R"(CREATE TABLE IF NOT EXISTS users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL CHECK(role IN('administrateur','enseignant','eleve','parent','comptable')),
            account_status TEXT NOT NULL DEFAULT 'active',
            suspended_until TEXT,
            blocked_reason TEXT,
            blocked_category TEXT,
            exam_dates_hidden INTEGER NOT NULL DEFAULT 0,
            requires_password_reset INTEGER NOT NULL DEFAULT 0,
            deleted_at TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS students(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            parent_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            matricule TEXT UNIQUE,
            last_name TEXT NOT NULL,
            first_name TEXT NOT NULL,
            birth_date TEXT NOT NULL,
            birth_place TEXT,
            father_name TEXT,
            father_job TEXT,
            mother_name TEXT,
            mother_job TEXT,
            parent_phone TEXT NOT NULL,
            parent_email TEXT,
            address TEXT NOT NULL,
            previous_school TEXT,
            previous_class TEXT,
            current_class TEXT NOT NULL,
            desired_career TEXT,
            graduated_at TEXT,
            consecutive_missed_payments INTEGER NOT NULL DEFAULT 0,
            photo TEXT,
            entry_date TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            deleted_at TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS guardians(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            full_name TEXT NOT NULL,
            phone TEXT NOT NULL,
            email TEXT,
            relation TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS student_guardians(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            guardian_id INTEGER NOT NULL REFERENCES guardians(id) ON DELETE CASCADE,
            is_primary INTEGER NOT NULL DEFAULT 0,
            UNIQUE(student_id, guardian_id)
        ))",

        R"(CREATE TABLE IF NOT EXISTS parent_student_links(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parent_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            UNIQUE(parent_user_id, student_id)
        ))",

        R"(CREATE TABLE IF NOT EXISTS settings(
            key TEXT PRIMARY KEY,
            value TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS academic_periods(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS class_tuitions(
            class_name TEXT PRIMARY KEY,
            monthly_amount REAL NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS permissions_catalog(
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

        R"(CREATE TABLE IF NOT EXISTS fee_types(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            default_amount REAL NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1
        ))",

        R"(CREATE TABLE IF NOT EXISTS one_time_fees(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            fee_type_id INTEGER NOT NULL REFERENCES fee_types(id),
            amount REAL NOT NULL,
            due_date TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            payment_id INTEGER REFERENCES payments(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS subjects(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            coefficient REAL NOT NULL DEFAULT 1
        ))",

        R"(CREATE TABLE IF NOT EXISTS class_assignments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_name TEXT NOT NULL,
            subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
            teacher_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            UNIQUE(class_name, subject_id)
        ))",

        R"(CREATE TABLE IF NOT EXISTS timetable_slots(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_name TEXT NOT NULL,
            weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 6),
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            subject_id INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
            room TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS attendance(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            day TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('present','absent','late','excused')),
            UNIQUE(student_id, day)
        ))",

        R"(CREATE TABLE IF NOT EXISTS incidents(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            incident_date TEXT NOT NULL,
            category TEXT NOT NULL,
            description TEXT,
            sanction TEXT,
            recorded_by INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS cycles(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            sort_order INTEGER NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS levels(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            cycle_id INTEGER NOT NULL REFERENCES cycles(id),
            sort_order INTEGER NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS school_classes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            level_id INTEGER NOT NULL REFERENCES levels(id),
            sort_order INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1
        ))",

        R"(CREATE TABLE IF NOT EXISTS rooms(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            capacity INTEGER NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS calendar_events(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('evenement','ferie','vacances'))
        ))",

        R"(CREATE TABLE IF NOT EXISTS document_history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            doc_type TEXT NOT NULL,
            ref_id INTEGER NOT NULL DEFAULT 0,
            label TEXT,
            user_id INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS cash_movements(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            movement_date TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('entree','sortie')),
            amount REAL NOT NULL,
            label TEXT NOT NULL,
            recorded_by INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS cash_closings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            closing_date TEXT NOT NULL UNIQUE,
            expected REAL NOT NULL,
            counted REAL NOT NULL,
            difference REAL NOT NULL,
            closed_by INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS bank_accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            bank TEXT,
            last4 TEXT,
            opening_balance REAL NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS bank_lines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id INTEGER NOT NULL REFERENCES bank_accounts(id) ON DELETE CASCADE,
            line_date TEXT NOT NULL,
            label TEXT NOT NULL,
            amount REAL NOT NULL,
            payment_id INTEGER UNIQUE REFERENCES payments(id) ON DELETE SET NULL
        ))",

        R"(CREATE TABLE IF NOT EXISTS payment_methods(
            code TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1
        ))",

        R"(CREATE TABLE IF NOT EXISTS payment_schedules(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            label TEXT NOT NULL,
            due_date TEXT NOT NULL,
            amount REAL NOT NULL
        ))",

        R"(CREATE TABLE IF NOT EXISTS payment_allocations(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payment_id INTEGER NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
            invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
            amount REAL NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS scholarships(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            label TEXT NOT NULL,
            percent REAL NOT NULL CHECK(percent > 0 AND percent <= 100),
            school_year TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS expense_categories(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
        ))",

        R"(CREATE TABLE IF NOT EXISTS email_log(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recipient TEXT NOT NULL,
            subject TEXT NOT NULL,
            status TEXT NOT NULL,
            error TEXT,
            user_id INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
            identity_number TEXT,
            cnaps_number TEXT,
            mle_number TEXT,
            contact TEXT,
            address TEXT,
            dob TEXT,
            place_of_birth TEXT,
            number_of_children INTEGER,
            marital_status TEXT,
            religion TEXT,
            subject TEXT,
            occupation TEXT,
            employment_type TEXT,
            hiring_date TEXT,
            contract_end_date TEXT,
            comment TEXT,
            photo TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS courses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            subject TEXT NOT NULL,
            class_name TEXT NOT NULL,
            description TEXT,
            teacher_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS course_resources(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            course_id INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            type TEXT NOT NULL CHECK(type IN('pdf','video','quiz')),
            file_path TEXT,
            url TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS exams(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            course_id INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            term TEXT NOT NULL,
            exam_date TEXT NOT NULL,
            max_score INTEGER NOT NULL DEFAULT 20,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS grades(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exam_id INTEGER NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            score REAL,
            comment TEXT,
            UNIQUE(exam_id, student_id)
        ))",

        R"(CREATE TABLE IF NOT EXISTS payments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            recorded_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            amount REAL NOT NULL,
            method TEXT NOT NULL,
            payer_role TEXT NOT NULL DEFAULT 'eleve',
            reference TEXT,
            paid_at TEXT NOT NULL,
            notes TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS student_fees(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            monthly_amount REAL NOT NULL,
            set_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS invoices(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            period_month TEXT NOT NULL,
            due_date TEXT NOT NULL,
            amount REAL NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            payment_id INTEGER REFERENCES payments(id) ON DELETE SET NULL,
            reminder_before_sent_at TEXT,
            reminder_late_sent_at TEXT,
            UNIQUE(student_id, period_month)
        ))",

        R"(CREATE TABLE IF NOT EXISTS messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            recipient_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            subject TEXT NOT NULL,
            body TEXT NOT NULL,
            read_at TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS announcements(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            event_date TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS exam_periods(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT,
            start_date TEXT,
            end_date TEXT,
            is_active INTEGER NOT NULL DEFAULT 0,
            activated_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS tardiness_records(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            recorded_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            occurred_at TEXT NOT NULL,
            note TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS notifications(
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            data TEXT NOT NULL,
            read_at TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS audit_logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            action TEXT NOT NULL,
            entity TEXT,
            entity_id INTEGER,
            details TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS chart_of_accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL UNIQUE,
            label TEXT NOT NULL,
            account_type TEXT NOT NULL DEFAULT 'general',
            active INTEGER NOT NULL DEFAULT 1
        ))",

        R"(CREATE TABLE IF NOT EXISTS journal_entries(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_date TEXT NOT NULL,
            journal_code TEXT NOT NULL,
            reference TEXT,
            description TEXT NOT NULL,
            source_type TEXT,
            source_id INTEGER,
            created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS journal_lines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id INTEGER NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
            account_code TEXT NOT NULL,
            label TEXT,
            debit REAL NOT NULL DEFAULT 0,
            credit REAL NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            expense_date TEXT NOT NULL,
            category TEXT NOT NULL,
            description TEXT NOT NULL,
            amount REAL NOT NULL,
            payment_method TEXT NOT NULL,
            reference TEXT,
            account_code TEXT NOT NULL DEFAULT '606000',
            recorded_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS accounting_periods(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL UNIQUE,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            closed INTEGER NOT NULL DEFAULT 0,
            closed_at TEXT
        ))"
    };

    for (const auto &sql : schema)
        if (!exec(sql)) return false;

    return true;
}

bool Database::columnExists(const QString &table, const QString &column)
{
    QSqlQuery q(m_db);
    if (!q.exec(QStringLiteral("PRAGMA table_info(%1)").arg(table))) return false;
    while (q.next())
        if (q.value(1).toString() == column) return true;
    return false;
}

bool Database::migrate()
{
    // Bases existantes : students.deleted_at n'existait pas (suppression logique cassée).
    if (!columnExists(QStringLiteral("students"), QStringLiteral("deleted_at"))
        && !exec("ALTER TABLE students ADD COLUMN deleted_at TEXT"))
        return false;

    // Bases existantes : date d'entrée/inscription ajoutée après coup.
    if (!columnExists(QStringLiteral("students"), QStringLiteral("entry_date"))
        && !exec("ALTER TABLE students ADD COLUMN entry_date TEXT"))
        return false;

    if (!columnExists(QStringLiteral("payments"), QStringLiteral("receipt_number"))
        && !exec("ALTER TABLE payments ADD COLUMN receipt_number TEXT"))
        return false;
    if (!exec("UPDATE payments SET receipt_number='REC-'||substr(paid_at,1,4)||'-'||printf('%05d',"
              "(SELECT COUNT(*) FROM payments p2 WHERE substr(p2.paid_at,1,4)=substr(payments.paid_at,1,4) AND p2.id<=payments.id)) "
              "WHERE receipt_number IS NULL"))
        return false;

    if (!exec("UPDATE students SET current_class='TL1' WHERE current_class IN ('T L1','Terminale L1')")) return false;
    if (!exec("UPDATE students SET current_class='TL2' WHERE current_class IN ('T L2','Terminale L2')")) return false;
    if (!exec("UPDATE students SET current_class='TS' WHERE current_class IN ('T S1','T S2','Terminale S')")) return false;

    // Anciennes versions : un compte administrateur codé en dur (admin@myschool.local / mot de passe
    // par défaut) était créé automatiquement. Tant qu'il porte encore le mot de passe par défaut,
    // on le retire (suppression logique + e-mail libéré) : l'écran de première configuration
    // s'affichera si plus aucun administrateur actif n'existe.
    QSqlQuery legacy(m_db);
    legacy.prepare("UPDATE users SET deleted_at=CURRENT_TIMESTAMP, account_status='blocked', "
                   "email='supprime+'||id||'@invalide.local' "
                   "WHERE email='admin@myschool.local' AND password_hash=? AND deleted_at IS NULL");
    legacy.addBindValue(legacyHashPassword(QStringLiteral("admin123")));
    if (!legacy.exec()) {
        qWarning() << legacy.lastError().text();
        return false;
    }
    return true;
}

bool Database::seed()
{
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('email.config','Configurer le serveur d''envoi et la planification','Communication')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','email.config',1),('enseignant','email.config',0),('eleve','email.config',0),('parent','email.config',0),('comptable','email.config',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('email.send','Envoyer des e-mails (relances, situations, tests)','Communication')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','email.send',1),('enseignant','email.send',0),('eleve','email.send',0),('parent','email.send',0),('comptable','email.send',1)")) return false;

    if (!exec("INSERT OR IGNORE INTO expense_categories(name) VALUES ('Fournitures'),('Salaires'),('Eau et électricité'),('Entretien'),('Transport'),('Autres')")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('payments.allocate','Affecter un paiement à une facture','Finances')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','payments.allocate',1),('enseignant','payments.allocate',0),('eleve','payments.allocate',0),('parent','payments.allocate',0),('comptable','payments.allocate',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('scholarships.manage','Gérer les bourses des élèves','Finances')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','scholarships.manage',1),('enseignant','scholarships.manage',0),('eleve','scholarships.manage',0),('parent','scholarships.manage',0),('comptable','scholarships.manage',1)")) return false;

    if (!exec("INSERT OR IGNORE INTO payment_methods(code,label,is_active) VALUES ('mvola','Mvola',1),('orange_money','Orange Money',1),('airtel_money','Airtel Money',1),('virement','Virement bancaire',1),('especes','Espèces',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('cash.manage','Gérer la caisse (mouvements et clôture)','Comptabilité')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','cash.manage',1),('enseignant','cash.manage',0),('eleve','cash.manage',0),('parent','cash.manage',0),('comptable','cash.manage',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('bank.manage','Gérer les comptes bancaires et le rapprochement','Comptabilité')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','bank.manage',1),('enseignant','bank.manage',0),('eleve','bank.manage',0),('parent','bank.manage',0),('comptable','bank.manage',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('closing.manage','Clôturer et rouvrir les périodes comptables','Comptabilité')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','closing.manage',1),('enseignant','closing.manage',0),('eleve','closing.manage',0),('parent','closing.manage',0),('comptable','closing.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('paymentmethods.manage','Gérer les moyens de paiement','Comptabilité')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','paymentmethods.manage',1),('enseignant','paymentmethods.manage',0),('eleve','paymentmethods.manage',0),('parent','paymentmethods.manage',0),('comptable','paymentmethods.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('schedule.manage','Gérer les échéanciers de paiement','Finances')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','schedule.manage',1),('enseignant','schedule.manage',0),('eleve','schedule.manage',0),('parent','schedule.manage',0),('comptable','schedule.manage',1)")) return false;

    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('finance.reports','Voir les rapports financiers (impayés, situations, tableau financier)','Finances')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','finance.reports',1),('enseignant','finance.reports',0),('eleve','finance.reports',0),('parent','finance.reports',0),('comptable','finance.reports',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('documents.history','Consulter l''historique des documents imprimés','Documents officiels')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','documents.history',1),('enseignant','documents.history',0),('eleve','documents.history',0),('parent','documents.history',0),('comptable','documents.history',1)")) return false;

    if (!exec("INSERT OR IGNORE INTO cycles(id,name,sort_order) VALUES (1,'Primaire',1),(2,'Collège',2),(3,'Lycée',3)")) return false;
    if (!exec("INSERT OR IGNORE INTO levels(id,name,cycle_id,sort_order) VALUES (1,'CP',1,1),(2,'CE',1,2),(3,'CM',1,3),(4,'6ème',2,4),(5,'5ème',2,5),(6,'4ème',2,6),(7,'3ème',2,7),(8,'2nde',3,8),(9,'1ère',3,9),(10,'Terminale',3,10)")) return false;
    if (!exec("INSERT OR IGNORE INTO school_classes(id,name,level_id,sort_order) VALUES (1,'CP1',1,1),(2,'CP2',1,2),(3,'CE1',2,3),(4,'CE2',2,4),(5,'CM1',3,5),(6,'CM2',3,6),(7,'6ème 1',4,7),(8,'6ème 2',4,8),(9,'6ème 3',4,9),(10,'5ème 1',5,10),(11,'5ème 2',5,11),(12,'5ème 3',5,12),(13,'4ème 1',6,13),(14,'4ème 2',6,14),(15,'4ème 3',6,15),(16,'3ème 1',7,16),(17,'3ème 2',7,17),(18,'3ème 3',7,18),(19,'2nde 1',8,19),(20,'2nde 2',8,20),(21,'2nde 3',8,21),(22,'2nde 4',8,22),(23,'1ère L1',9,23),(24,'1ère L2',9,24),(25,'1ère S1',9,25),(26,'1ère S2',9,26),(27,'TL1',10,27),(28,'TL2',10,28),(29,'TS',10,29)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('structure.manage','Gérer cycles, niveaux, classes et salles','Administration scolaire')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','structure.manage',1),('enseignant','structure.manage',0),('eleve','structure.manage',0),('parent','structure.manage',0),('comptable','structure.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('calendar.manage','Gérer le calendrier scolaire et les jours fériés','Administration scolaire')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','calendar.manage',1),('enseignant','calendar.manage',0),('eleve','calendar.manage',0),('parent','calendar.manage',0),('comptable','calendar.manage',0)")) return false;

    if (!exec("INSERT OR IGNORE INTO settings(key,value) VALUES ('pass_mark','10'),('retake_mark','8')"))
        return false;

    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('subjects.manage','Gérer les matières','Pédagogie')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','subjects.manage',1),('enseignant','subjects.manage',0),('eleve','subjects.manage',0),('parent','subjects.manage',0),('comptable','subjects.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('assignments.manage','Affecter les enseignants aux classes','Pédagogie')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','assignments.manage',1),('enseignant','assignments.manage',0),('eleve','assignments.manage',0),('parent','assignments.manage',0),('comptable','assignments.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('timetable.manage','Gérer l''emploi du temps','Pédagogie')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','timetable.manage',1),('enseignant','timetable.manage',0),('eleve','timetable.manage',0),('parent','timetable.manage',0),('comptable','timetable.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('attendance.record','Saisir les présences','Vie scolaire')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','attendance.record',1),('enseignant','attendance.record',1),('eleve','attendance.record',0),('parent','attendance.record',0),('comptable','attendance.record',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('discipline.record','Enregistrer les incidents disciplinaires','Vie scolaire')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','discipline.record',1),('enseignant','discipline.record',1),('eleve','discipline.record',0),('parent','discipline.record',0),('comptable','discipline.record',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('deliberations.view','Voir les délibérations','Pédagogie')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','deliberations.view',1),('enseignant','deliberations.view',1),('eleve','deliberations.view',0),('parent','deliberations.view',0),('comptable','deliberations.view',0)")) return false;

    if (!exec("INSERT OR IGNORE INTO fee_types(name,default_amount) VALUES ('Frais d''inscription',0),('Uniforme',0),('Frais d''examen',0),('Carte scolaire',0)"))
        return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES ('fees.onetime.manage','Gérer les types de frais ponctuels et les assigner','Finances')"))
        return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES ('fees.onetime.pay','Encaisser les frais ponctuels','Finances')"))
        return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','fees.onetime.manage',1),('enseignant','fees.onetime.manage',0),('eleve','fees.onetime.manage',0),('parent','fees.onetime.manage',0),('comptable','fees.onetime.manage',1),('administrateur','fees.onetime.pay',1),('enseignant','fees.onetime.pay',0),('eleve','fees.onetime.pay',0),('parent','fees.onetime.pay',0),('comptable','fees.onetime.pay',1)"))
        return false;

    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('students.view','Voir les élèves et leurs fiches','Élèves')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','students.view',1),('enseignant','students.view',1),('eleve','students.view',0),('parent','students.view',0),('comptable','students.view',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('students.create','Inscrire un élève','Élèves')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','students.create',1),('enseignant','students.create',1),('eleve','students.create',0),('parent','students.create',0),('comptable','students.create',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('students.edit','Modifier une fiche élève','Élèves')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','students.edit',1),('enseignant','students.edit',1),('eleve','students.edit',0),('parent','students.edit',0),('comptable','students.edit',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('students.block','Bloquer ou débloquer un élève','Élèves')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','students.block',1),('enseignant','students.block',1),('eleve','students.block',0),('parent','students.block',0),('comptable','students.block',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('students.delete','Supprimer un élève ou le marquer diplômé','Élèves')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','students.delete',1),('enseignant','students.delete',0),('eleve','students.delete',0),('parent','students.delete',0),('comptable','students.delete',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('guardians.read','Voir les parents et tuteurs','Élèves')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','guardians.read',1),('enseignant','guardians.read',1),('eleve','guardians.read',0),('parent','guardians.read',0),('comptable','guardians.read',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('guardians.add','Ajouter un tuteur','Élèves')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','guardians.add',1),('enseignant','guardians.add',1),('eleve','guardians.add',0),('parent','guardians.add',0),('comptable','guardians.add',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('guardians.remove','Retirer un tuteur','Élèves')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','guardians.remove',1),('enseignant','guardians.remove',0),('eleve','guardians.remove',0),('parent','guardians.remove',0),('comptable','guardians.remove',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('parents.link','Lier un compte parent à un élève','Élèves')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','parents.link',1),('enseignant','parents.link',0),('eleve','parents.link',0),('parent','parents.link',0),('comptable','parents.link',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('teachers.manage','Gérer les enseignants','Personnel')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','teachers.manage',1),('enseignant','teachers.manage',0),('eleve','teachers.manage',0),('parent','teachers.manage',0),('comptable','teachers.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('courses.manage','Gérer les cours et ressources','Pédagogie')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','courses.manage',1),('enseignant','courses.manage',1),('eleve','courses.manage',0),('parent','courses.manage',0),('comptable','courses.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('exams.manage','Gérer les examens','Pédagogie')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','exams.manage',1),('enseignant','exams.manage',1),('eleve','exams.manage',0),('parent','exams.manage',0),('comptable','exams.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('grades.edit','Saisir les notes','Pédagogie')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','grades.edit',1),('enseignant','grades.edit',1),('eleve','grades.edit',0),('parent','grades.edit',0),('comptable','grades.edit',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('tardiness.record','Enregistrer les retards','Vie scolaire')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','tardiness.record',1),('enseignant','tardiness.record',1),('eleve','tardiness.record',0),('parent','tardiness.record',0),('comptable','tardiness.record',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('payments.create','Enregistrer un paiement','Finances')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','payments.create',1),('enseignant','payments.create',0),('eleve','payments.create',0),('parent','payments.create',0),('comptable','payments.create',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('fees.student','Définir le tarif individuel d''un élève','Finances')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','fees.student',1),('enseignant','fees.student',0),('eleve','fees.student',0),('parent','fees.student',0),('comptable','fees.student',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('fees.tuition','Modifier la grille tarifaire par classe','Finances')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','fees.tuition',1),('enseignant','fees.tuition',0),('eleve','fees.tuition',0),('parent','fees.tuition',0),('comptable','fees.tuition',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('invoices.generate','Générer les factures mensuelles','Finances')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','invoices.generate',1),('enseignant','invoices.generate',0),('eleve','invoices.generate',0),('parent','invoices.generate',0),('comptable','invoices.generate',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('invoices.remind','Lancer les relances de paiement','Finances')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','invoices.remind',1),('enseignant','invoices.remind',0),('eleve','invoices.remind',0),('parent','invoices.remind',0),('comptable','invoices.remind',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('balances.view','Voir la vue d''ensemble des soldes','Finances')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','balances.view',1),('enseignant','balances.view',0),('eleve','balances.view',0),('parent','balances.view',0),('comptable','balances.view',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('accounting.write','Saisir les écritures et les dépenses','Comptabilité')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','accounting.write',1),('enseignant','accounting.write',0),('eleve','accounting.write',0),('parent','accounting.write',0),('comptable','accounting.write',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('accounting.export','Exporter la comptabilité','Comptabilité')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','accounting.export',1),('enseignant','accounting.export',0),('eleve','accounting.export',0),('parent','accounting.export',0),('comptable','accounting.export',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('communication.announcements','Publier et supprimer des annonces','Communication')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','communication.announcements',1),('enseignant','communication.announcements',0),('eleve','communication.announcements',0),('parent','communication.announcements',0),('comptable','communication.announcements',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('users.manage','Créer des comptes, changer un rôle, réinitialiser un mot de passe','Comptes')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','users.manage',1),('enseignant','users.manage',0),('eleve','users.manage',0),('parent','users.manage',0),('comptable','users.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('users.block','Bloquer un compte','Comptes')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','users.block',1),('enseignant','users.block',1),('eleve','users.block',0),('parent','users.block',0),('comptable','users.block',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('users.unblock','Débloquer un compte','Comptes')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','users.unblock',1),('enseignant','users.unblock',0),('eleve','users.unblock',0),('parent','users.unblock',0),('comptable','users.unblock',1)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('periods.manage','Gérer les périodes académiques et d''examen','Administration')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','periods.manage',1),('enseignant','periods.manage',0),('eleve','periods.manage',0),('parent','periods.manage',0),('comptable','periods.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('settings.manage','Modifier les paramètres de l''établissement','Administration')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','settings.manage',1),('enseignant','settings.manage',0),('eleve','settings.manage',0),('parent','settings.manage',0),('comptable','settings.manage',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('audit.view','Consulter le journal d''audit','Administration')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','audit.view',1),('enseignant','audit.view',0),('eleve','audit.view',0),('parent','audit.view',0),('comptable','audit.view',0)")) return false;
    if (!exec("INSERT OR IGNORE INTO permissions_catalog(key,label,grp) VALUES('roles.manage','Gérer les rôles et les permissions','Administration')")) return false;
    if (!exec("INSERT OR IGNORE INTO role_permissions(role,permission,allowed) VALUES ('administrateur','roles.manage',1),('enseignant','roles.manage',0),('eleve','roles.manage',0),('parent','roles.manage',0),('comptable','roles.manage',0)")) return false;

    if (!exec("INSERT OR IGNORE INTO settings(key,value) VALUES('school_name','Ecole Sacré-Cœur'),"
              "('school_city','Tolagnaro'),('signatory_title','Le Frère Directeur')"))
        return false;

    const QStringList accounts = {
        "411000|Parents / familles|client",
        "401000|Fournisseurs|supplier",
        "512000|Banque|bank",
        "531000|Caisse|cash",
        "580000|Transferts internes|treasury",
        "606000|Achats et charges diverses|expense",
        "641000|Salaires et charges|expense",
        "706000|Écolages / prestations scolaires|revenue",
        "758000|Autres produits|revenue"
    };
    for (const auto &a : accounts) {
        const auto parts = a.split('|');
        QSqlQuery aq(m_db);
        aq.prepare("INSERT OR IGNORE INTO chart_of_accounts(code,label,account_type) VALUES(?,?,?)");
        aq.addBindValue(parts.value(0));
        aq.addBindValue(parts.value(1));
        aq.addBindValue(parts.value(2));
        if (!aq.exec()) return false;
    }

    return true;
}
