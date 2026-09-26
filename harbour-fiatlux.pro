TARGET = harbour-fiatlux

CONFIG += sailfishapp

SOURCES += \
    src/harbour-fiatlux.cpp \
    src/camera2meter.cpp

HEADERS += \
    src/camera2meter.h

REQUIRED_FILES = \
    $${TARGET}.desktop \
    qml/$${TARGET}.qml \
    qml/qmldir \
    qml/Storage.js \
    LICENSE \
    LICENSE.RAWfish

for(f, REQUIRED_FILES) {
    !exists($$PWD/$$f): error("Missing $$f -- expected it at $$PWD/$$f")
}

isEmpty(APP_VERSION) {
    APP_VERSION = 0.0.0-dev
}
DEFINES += APP_VERSION=\\\"$$APP_VERSION\\\"

licensefile.files = $$PWD/LICENSE $$PWD/LICENSE.RAWfish
licensefile.path = /usr/share/licenses/$${TARGET}
INSTALLS += licensefile

DISTFILES += \
    $$files(qml/*.qml) \
    $$files(qml/components/*.qml) \
    $$files(qml/cover/*.qml) \
    $$files(qml/pages/*.qml) \
    qml/qmldir \
    qml/Storage.js \
    $${TARGET}.desktop \
    rpm/$${TARGET}.spec

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172
