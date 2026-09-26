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

# ---- the camera ----
#
# Fiat Lux carries its own copy of RAWfish's Camera2 bridge (camera2/, see its
# README), so RAWfish does not have to be installed.
#
# The Sailfish half is one C file, built here next to the app:
#   /usr/libexec/harbour-fiatlux/camera2-helper
# The Android half cannot be built by the Sailfish SDK. It is built once with
# the Android NDK (or copied from a phone with RAWfish) into camera2/prebuilt/
# and installed where libhybris looks for Android libraries.

CAMERA2_HELPER_SRC = $$PWD/camera2/sailfish/main.c
camera2helper.target = camera2-helper
camera2helper.depends = $$CAMERA2_HELPER_SRC $$PWD/camera2/android/camera2_bridge.h
camera2helper.commands = $$QMAKE_CC $$QMAKE_CFLAGS_RELEASE -std=c11 -Wall -o camera2-helper $$CAMERA2_HELPER_SRC -ldl
QMAKE_EXTRA_TARGETS += camera2helper
PRE_TARGETDEPS += camera2-helper
QMAKE_CLEAN += camera2-helper

camera2helper_install.files = $$OUT_PWD/camera2-helper
camera2helper_install.path = /usr/libexec/$${TARGET}
camera2helper_install.CONFIG += no_check_exist executable
INSTALLS += camera2helper_install

CAMERA2_BRIDGE = $$PWD/camera2/prebuilt/libfiatluxcamera2.so
!exists($$CAMERA2_BRIDGE): error("Missing camera2/prebuilt/libfiatluxcamera2.so. Run camera2/fetch-bridge.sh to copy it from a phone with RAWfish, or camera2/build-bridge.sh to build it with the Android NDK. See camera2/README.md.")
camera2bridge.files = $$CAMERA2_BRIDGE
camera2bridge.path = /usr/libexec/droid-hybris/system/lib64
INSTALLS += camera2bridge

DISTFILES += \
    $$files(qml/*.qml) \
    $$files(qml/components/*.qml) \
    $$files(qml/cover/*.qml) \
    $$files(qml/pages/*.qml) \
    qml/qmldir \
    qml/Storage.js \
    $${TARGET}.desktop \
    qml/Gear.js \
    qml/FilmCatalogue.js \
    $$files(camera2/*.sh) \
    $$files(camera2/*.md) \
    $$files(camera2/android/*) \
    $$files(camera2/sailfish/*) \
    rpm/$${TARGET}.spec

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172
