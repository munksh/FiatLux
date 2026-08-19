TARGET = FiatLux
CONFIG += sailfishapp

SOURCES += src/FiatLux.cpp

DISTFILES += \
    qml/FiatLux.qml \
    qml/qmldir \
    qml/FiatLuxTheme.qml \
    qml/Storage.js \
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

SAILFISHAPP_ICONS = 86x86 108x108 128x128 256x256

CONFIG += sailfishapp_i18n
TRANSLATIONS += translations/FiatLux-eng_en.ts
