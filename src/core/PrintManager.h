#pragma once
#include <QObject>
#include <QString>
class PrintManager : public QObject
{
    Q_OBJECT
public:
    explicit PrintManager(QObject *parent = nullptr);
    Q_INVOKABLE bool printStudentList(const QString &className = QString());
    Q_INVOKABLE bool printTeacherList();
    Q_INVOKABLE bool exportStudentsPdf(const QString &path, const QString &className = QString());
};
