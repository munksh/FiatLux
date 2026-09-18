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

    // `import "." 1.0` at the top is not decoration. Singletons declared in
    // qmldir are NOT resolved by the implicit import of a file's own
    // directory -- only by an explicit one. Without that line FiatLuxTheme was
    // simply not defined here, and the pages worked only because they say
    // import ".." 1.0 themselves.

    // Order matters, and the try/catch is not paranoia.
    //
    // A ReferenceError anywhere in onCompleted aborts the WHOLE block, and
    // says nothing about what never ran. When FiatLuxTheme failed to resolve
    // on the first line of this handler, Storage.init() silently did not
    // happen -- an uninitialised database, with the only error message
    // pointing at a colour palette.
    //
    // So: the things the app cannot work without go first, and the ones it can
    // limp without are guarded. A missing palette is an ugly app. A missing
    // database is no app.
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
            console.log("theme not reachable from FiatLux.qml:", e)
        }

        // Asks the camera what it can actually report about its own exposure,
        // and writes the answer to the log. QML's CameraExposure exposes the
        // values but not the capabilities -- there is no isAvailable() and no
        // supportedShutterSpeeds() -- so from QML the only way to find out is
        // to read a zero and interpret it, which is guessing.
        //
        // Guarded on purpose: exposureProbe is a context property from C++, so
        // it does not exist in a build without it, and a missing probe must
        // never be the reason the app fails to start. Delete this block once
        // the question is answered.
        try {
            if (typeof exposureProbe !== "undefined" && exposureProbe !== null) {
                exposureProbe.run()
            }
        } catch (e2) {
            console.log("exposure probe not available:", e2)
        }
    }
}
