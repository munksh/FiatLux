import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"
import "Storage.js" as Storage

ApplicationWindow {
    id: app

    property ListModel cameraModel: ListModel {}

    Component.onCompleted: {
        Storage.init()
        Storage.loadCameras(cameraModel)
    }

    initialPage: Component { FirstPage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations
}
