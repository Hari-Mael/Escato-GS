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

private:
    QSqlDatabase m_db;
    bool createSchema();
    bool migrate();
    bool seed();
};
