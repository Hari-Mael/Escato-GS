#pragma once
#include <QObject>
#include <QSqlDatabase>
#include <QString>

class Database : public QObject
{
    Q_OBJECT
public:
    explicit Database(QObject *parent = nullptr);
    bool open();
    bool exec(const QString &sql);
    QSqlDatabase db() const { return m_db; }
    QString lastError() const;

    static QString hashPassword(const QString &password);
    static bool verifyPassword(const QString &password, const QString &stored);
    static bool needsRehash(const QString &stored);

private:
    QSqlDatabase m_db;
    bool createSchema();
    bool migrate();
    bool seed();
    bool columnExists(const QString &table, const QString &column);
};
