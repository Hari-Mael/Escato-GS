#include <QApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QMessageBox>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQmlContext>
#include <QTextStream>
#include <QUrl>
#include "core/SchoolApp.h"
#include "core/PrintManager.h"

namespace {
void journaliserMessage(QtMsgType, const QMessageLogContext &, const QString &message)
{
    QFile fichier(QDir::tempPath() + QStringLiteral("/escato-qml.log"));
    if (fichier.open(QIODevice::Append | QIODevice::Text)) {
        QTextStream flux(&fichier);
        flux << QDateTime::currentDateTime().toString(Qt::ISODate) << ' ' << message << '\n';
    }
}
}

int main(int argc, char *argv[])
{
    qInstallMessageHandler(journaliserMessage);

    QApplication app(argc, argv);
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QApplication::setOrganizationName("ESCATO");
    QApplication::setApplicationName("ESCATO");
    QApplication::setApplicationVersion("1.0.0");

    SchoolApp school;
    PrintManager printer;
    printer.setSchool(&school);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("school", &school);
    engine.rootContext()->setContextProperty("printer", &printer);

    const QUrl url(QStringLiteral("qrc:/ESCATO/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] {
                         QMessageBox::critical(nullptr, QStringLiteral("ESCATO"),
                             QStringLiteral("Impossible de charger l'interface. Contactez l'administrateur."));
                         QCoreApplication::exit(-1);
                     },
                     Qt::QueuedConnection);
    engine.load(url);
    if (engine.rootObjects().isEmpty())
        return -1;
    return app.exec();
}
