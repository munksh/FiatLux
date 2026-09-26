import QtQuick 2.0
import Sailfish.Silica 1.0
import "." 1.0
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

    // `import "." 1.0` is what makes the qmldir singleton visible in this file;
    // the implicit import of a file's own directory does not resolve it.

    // The database first and unguarded: a ReferenceError aborts the whole
    // handler, and an app without its palette is ugly, one without its
    // database is broken.
    Component.onCompleted: {
        Storage.init()
        reloadCameras()
        reloadLenses()
        reloadStocks()
        reloadRolls()

        try {
            FiatLuxTheme.window = app
            FiatLuxTheme.applyPalette(app)
        } catch (e) {
            console.log("theme not reachable from the root:", e)
        }
    }
}
