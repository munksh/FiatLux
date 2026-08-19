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

    // Silica's own chrome -- menus, pull-down drawers, ComboBox values,
    // TextField labels and underlines, sliders, selection -- does not take a
    // colour from FiatLuxTheme. It reads Theme.* directly, which is the
    // ambience. Under Fiat colours that is light text on light paper, and no
    // amount of `color:` on individual items fixes it, because most of those
    // surfaces do not expose a colour property at all.
    //
    // `palette` is Silica's answer: colour roles that hang off an item and are
    // inherited by its children. Set once here, every control in every page
    // below follows. Do this before hunting individual `color:` properties --
    // it is the difference between a themed app and an app with themed
    // patches.
    Component.onCompleted: {
        FiatLuxTheme.applyPalette(app)
        Storage.init()
        reloadCameras()
        reloadLenses()
        reloadStocks()
        reloadRolls()
    }

    // Re-apply rather than revert. Under an ambience applyPalette feeds Silica
    // back its own Theme.* values, so the switch round-trips cleanly without
    // anyone having to remember the originals.
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: FiatLuxTheme.applyPalette(app)
    }
}
