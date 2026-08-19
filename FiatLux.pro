TARGET = FiatLux

CONFIG += sailfishapp

SOURCES += src/FiatLux.cpp

# Everything listed here gets deployed to /usr/share/FiatLux/.
# Storage.js and qmldir MUST be listed or they silently do not ship, and the
# app dies with "FiatLuxTheme is not a type".
DISTFILES += \
    qml/FiatLux.qml \
    qml/qmldir \
    qml/FiatLuxTheme.qml \
    qml/Storage.js \
    qml/components/PaperBackground.qml \
    qml/cover/CoverPage.qml \
    qml/pages/MeterPage.qml \
    qml/pages/CamerasPage.qml \
    qml/pages/AddCameraPage.qml \
    qml/pages/LensesPage.qml \
    qml/pages/AddLensPage.qml \
    qml/pages/FilmPage.qml \
    qml/pages/AddStockPage.qml \
    qml/pages/AddRollPage.qml \
    qml/pages/ShotsPage.qml \
    qml/pages/CardSection.qml \
    qml/pages/ChooserRow.qml \
    qml/pages/PillMenu.qml \
    rpm/FiatLux.spec

# 256x256 is not a Sailfish icon size and 172x172 is required by Harbour.
# Fixed in the harbour- rename, together with TARGET and the spec.
SAILFISHAPP_ICONS = 86x86 108x108 128x128 256x256

# Translations are not wired up. The old line pointed at
# translations/FiatLux-eng_en.ts, which does not exist -- the files on disk
# are FiatLux.ts and a FiatLux-de.ts that looks like template residue.
# CONFIG += sailfishapp_i18n
# TRANSLATIONS += translations/FiatLux-sv.ts
