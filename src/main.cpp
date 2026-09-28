#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>
#include "core/SchoolApp.h"
#include "core/PrintManager.h"

int main(int argc, char *argv[])
{
    // QApplication (et non QGuiApplication) : QPrintDialog est un widget.
    QApplication app(argc, argv);
    QApplication::setOrganizationName("ESCATO");
    QApplication::setApplicationName("ESCATO");
    QApplication::setApplicationVersion("1.0.0");

    SchoolApp school;
    PrintManager printer;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("school", &school);
    engine.rootContext()->setContextProperty("printer", &printer);

    const QUrl url(QStringLiteral("qrc:/qt/qml/ESCATO/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    engine.load(url);
    return app.exec();
}
