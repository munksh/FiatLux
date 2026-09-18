#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>

#include "exposureprobe.h"

int main(int argc, char *argv[])
{
    // The long form of SailfishApp::main(), because we need the root context
    // to hand the probe to QML. Registered as a context property rather than
    // a type: there is exactly one of it, and the cover would not see a type.
    QGuiApplication *app = SailfishApp::application(argc, argv);
    QQuickView *view = SailfishApp::createView();

    ExposureProbe probe;
    view->rootContext()->setContextProperty("exposureProbe", &probe);

    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    return app->exec();
}
