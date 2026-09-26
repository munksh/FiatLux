#include <QtQuick>
#include <sailfishapp.h>

#include "camera2meter.h"

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    qmlRegisterType<Camera2Meter>("se.munkstolen.fiatlux", 1, 0, "Camera2Meter");
    QScopedPointer<QQuickView> view(SailfishApp::createView());
    view->rootContext()->setContextProperty(QStringLiteral("appVersion"), QString::fromUtf8(APP_VERSION));
    view->setSource(SailfishApp::pathToMainQml());
    view->show();
    return app->exec();
}
