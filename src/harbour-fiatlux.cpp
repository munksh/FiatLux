#include <QtQuick>
#include <sailfishapp.h>

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    QScopedPointer<QQuickView> view(SailfishApp::createView());
    view->rootContext()->setContextProperty(QStringLiteral("appVersion"), QString::fromUtf8(APP_VERSION));
    view->setSource(SailfishApp::pathToMainQml());
    view->show();
    return app->exec();
}
