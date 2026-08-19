import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"
import "Storage.js" as Storage

ApplicationWindow {
    id: app

    property ListModel cameraModel: ListModel {}
    property ListModel lensModel:   ListModel {}
    property ListModel stockModel:  ListModel {}
    property ListModel rollModel:   ListModel {}

    function reloadCameras() { Storage.loadCameras(cameraModel) }
    function reloadLenses()  { Storage.loadLenses(lensModel) }
    function reloadStocks()  { Storage.loadStocks(stockModel) }
    function reloadRolls()   { Storage.loadRolls(rollModel, false) }

    initialPage: Component { MeterPage {} }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    Component.onCompleted: {
        Storage.init()
        reloadCameras()
        reloadLenses()
        reloadStocks()
        reloadRolls()
    }
}
