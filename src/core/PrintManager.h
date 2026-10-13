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
    Q_INVOKABLE bool printStudentCertificate(int studentId);
    Q_INVOKABLE bool exportStudentCertificatePdf(const QString &path, int studentId);
    Q_INVOKABLE bool printStudentCard(int studentId);
    Q_INVOKABLE bool exportStudentCardPdf(const QString &path, int studentId);
    Q_INVOKABLE bool printReceipt(int paymentId);
    Q_INVOKABLE bool exportReceiptPdf(const QString &path, int paymentId);
    Q_INVOKABLE bool printPaymentRequest(int studentId);
    Q_INVOKABLE bool exportPaymentRequestPdf(const QString &path, int studentId);
    Q_INVOKABLE bool printAttestation(int studentId, const QString &kind);
    Q_INVOKABLE bool exportAttestationPdf(const QString &path, int studentId, const QString &kind);
    Q_INVOKABLE bool printBulletin(int studentId, const QString &term);
    Q_INVOKABLE bool exportBulletinPdf(const QString &path, int studentId, const QString &term);
};
