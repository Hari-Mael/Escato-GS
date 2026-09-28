#include "Database.h"
#include <QStandardPaths>
#include <QDir>
#include <QSqlQuery>
#include <QSqlError>
#include <QCryptographicHash>
#include <QDebug>

static QString hashPassword(const QString &s)
{
    return QString(QCryptographicHash::hash(s.toUtf8(), QCryptographicHash::Sha256).toHex());
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
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            deleted_at TEXT
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

bool Database::migrate()
{
    // Bases existantes : students.deleted_at n'existait pas (suppression logique cassée).
    QSqlQuery q(m_db);
    if (!q.exec("PRAGMA table_info(students)")) return false;
    bool hasDeletedAt = false;
    while (q.next())
        if (q.value(1).toString() == "deleted_at") hasDeletedAt = true;
    if (!hasDeletedAt && !exec("ALTER TABLE students ADD COLUMN deleted_at TEXT"))
        return false;

    // Anciennes versions : un compte administrateur codé en dur (admin@myschool.local / mot de passe
    // par défaut) était créé automatiquement. Tant qu'il porte encore le mot de passe par défaut,
    // on le retire (suppression logique + e-mail libéré) : l'écran de première configuration
    // s'affichera si plus aucun administrateur actif n'existe.
    QSqlQuery legacy(m_db);
    legacy.prepare("UPDATE users SET deleted_at=CURRENT_TIMESTAMP, account_status='blocked', "
                   "email='supprime+'||id||'@invalide.local' "
                   "WHERE email='admin@myschool.local' AND password_hash=? AND deleted_at IS NULL");
    legacy.addBindValue(hashPassword(QStringLiteral("admin123")));
    if (!legacy.exec()) {
        qWarning() << legacy.lastError().text();
        return false;
    }
    return true;
}

bool Database::seed()
{
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
