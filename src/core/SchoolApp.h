#pragma once
#include <QObject>
#include <QVariantList>
#include <QStringList>
#include "Database.h"

class SchoolApp : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loggedIn READ loggedIn NOTIFY sessionChanged)
    Q_PROPERTY(QString currentUser READ currentUser NOTIFY sessionChanged)
    Q_PROPERTY(QString currentRole READ currentRole NOTIFY sessionChanged)
    Q_PROPERTY(bool needsSetup READ needsSetup NOTIFY sessionChanged)
    Q_PROPERTY(int studentCount READ studentCount NOTIFY dataChanged)
    Q_PROPERTY(int teacherCount READ teacherCount NOTIFY dataChanged)
    Q_PROPERTY(int courseCount READ courseCount NOTIFY dataChanged)
    Q_PROPERTY(int pendingInvoiceCount READ pendingInvoiceCount NOTIFY dataChanged)

public:
    explicit SchoolApp(QObject *parent = nullptr);

    bool loggedIn() const { return m_userId > 0; }
    QString currentUser() const { return m_userName; }
    QString currentRole() const { return m_role; }
    // Vrai tant qu'aucun administrateur actif n'existe : l'application propose alors de le créer.
    bool needsSetup() const;

    int studentCount() const;
    int teacherCount() const;
    int courseCount() const;
    int pendingInvoiceCount() const;

    Q_INVOKABLE bool createFirstAdmin(const QString &name, const QString &email, const QString &password);
    Q_INVOKABLE bool login(const QString &email, const QString &password);
    Q_INVOKABLE void logout();

    Q_INVOKABLE QStringList classes() const;
    Q_INVOKABLE QStringList roles() const;
    Q_INVOKABLE QStringList paymentMethods() const;
    Q_INVOKABLE QStringList terms() const;

    Q_INVOKABLE QVariantList students(const QString &className = QString(), const QString &search = QString()) const;
    Q_INVOKABLE QVariantMap student(int id) const;
    Q_INVOKABLE bool addStudent(const QVariantMap &v);
    Q_INVOKABLE bool updateStudent(int id, const QVariantMap &v);
    Q_INVOKABLE bool deleteStudent(int id);
    Q_INVOKABLE bool graduateStudent(int id);
    Q_INVOKABLE bool blockStudent(int id, const QString &reason);
    Q_INVOKABLE bool unblockStudent(int id);

    Q_INVOKABLE QVariantList teachers(const QString &search = QString()) const;
    Q_INVOKABLE bool addTeacher(const QVariantMap &v);
    Q_INVOKABLE bool updateTeacher(int id, const QVariantMap &v);
    Q_INVOKABLE bool deleteTeacher(int id);

    Q_INVOKABLE QVariantList courses(const QString &className = QString()) const;
    Q_INVOKABLE bool addCourse(const QVariantMap &v);
    Q_INVOKABLE bool updateCourse(int id, const QVariantMap &v);
    Q_INVOKABLE bool deleteCourse(int id);

    Q_INVOKABLE QVariantList resources(int courseId) const;
    Q_INVOKABLE bool addResource(const QVariantMap &v);
    Q_INVOKABLE bool deleteResource(int id);

    Q_INVOKABLE QVariantList exams() const;
    Q_INVOKABLE bool addExam(const QVariantMap &v);
    Q_INVOKABLE bool updateExam(int id, const QVariantMap &v);
    Q_INVOKABLE bool deleteExam(int id);

    Q_INVOKABLE QVariantList grades(int examId) const;
    Q_INVOKABLE bool saveGrade(int examId, int studentId, double score, const QString &comment);
    Q_INVOKABLE QVariantMap bulletin(int studentId, const QString &term) const;

    Q_INVOKABLE QVariantList payments(int studentId = 0) const;
    Q_INVOKABLE bool addPayment(const QVariantMap &v);
    Q_INVOKABLE QVariantList invoices(const QString &status = QString()) const;
    Q_INVOKABLE QVariantList studentInvoices(int studentId) const;
    Q_INVOKABLE bool setStudentFee(int studentId, double amount);
    Q_INVOKABLE bool generateMonthlyInvoices(const QString &month);
    Q_INVOKABLE bool processPaymentReminders();

    // Comptabilité : caisse, banque, journal, plan comptable et exports
    Q_INVOKABLE QVariantMap accountingDashboard() const;
    Q_INVOKABLE QVariantList chartOfAccounts() const;
    Q_INVOKABLE bool addAccount(const QString &code, const QString &label, const QString &type);
    Q_INVOKABLE QVariantList expenses() const;
    Q_INVOKABLE bool addExpense(const QVariantMap &v);
    Q_INVOKABLE QVariantList journal(const QString &fromDate = QString(), const QString &toDate = QString()) const;
    Q_INVOKABLE QVariantList trialBalance(const QString &fromDate = QString(), const QString &toDate = QString()) const;
    Q_INVOKABLE QVariantList generalLedger(const QString &accountCode, const QString &fromDate = QString(), const QString &toDate = QString()) const;
    Q_INVOKABLE QString accountingExportDirectory() const;
    Q_INVOKABLE bool exportAccountingCsv(const QString &kind, const QString &filePath = QString()) const;

    Q_INVOKABLE QVariantList messages() const;
    Q_INVOKABLE bool sendMessage(int recipientId, const QString &subject, const QString &body);
    Q_INVOKABLE QVariantList users(const QString &role = QString()) const;
    Q_INVOKABLE bool createUser(const QVariantMap &v);
    Q_INVOKABLE bool updateUserRole(int id, const QString &role);
    Q_INVOKABLE bool blockUser(int id, const QString &category, const QString &reason);
    Q_INVOKABLE bool unblockUser(int id);

    Q_INVOKABLE QVariantList announcements() const;
    Q_INVOKABLE bool addAnnouncement(const QVariantMap &v);
    Q_INVOKABLE bool deleteAnnouncement(int id);

    Q_INVOKABLE QVariantList tardiness() const;
    Q_INVOKABLE bool addTardiness(const QVariantMap &v);

    Q_INVOKABLE QVariantList examPeriods() const;
    Q_INVOKABLE bool addExamPeriod(const QVariantMap &v);
    Q_INVOKABLE bool toggleExamPeriod(int id);

    Q_INVOKABLE QVariantList dashboard() const;
    Q_INVOKABLE bool resetPassword(int userId, const QString &newPassword);

signals:
    void sessionChanged();
    void dataChanged();
    void errorOccurred(const QString &message);

private:
    Database m_db;
    int m_userId = 0;
    QString m_userName;
    QString m_role;

    bool allowed(const QStringList &roles) const;
    void audit(const QString &action, const QString &entity, int entityId, const QString &details = QString());
    bool execute(const QString &sql, const QVariantList &bind = {});
};
