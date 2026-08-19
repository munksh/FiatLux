pragma Singleton
import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

QtObject {
    id: t

    // ── Mode ──────────────────────────────────────────────────────────────
    // ambient = true   → follow the user's Sailfish ambience
    // ambient = false  → fixed Fiat Lux darkroom palette
    property bool ambient: true

    property QtObject _cfg: ConfigurationValue {
        key: "/apps/fiatlux/ambient"
        defaultValue: true
        onValueChanged: t.ambient = value
        Component.onCompleted: t.ambient = value
    }

    function setAmbient(on) { _cfg.value = on }

    readonly property bool _dark: Theme.colorScheme === Theme.LightOnDark

    // ── Fixed Fiat Lux palette ────────────────────────────────────────────
    readonly property color fxDeepBg:        "#1E1A12"
    readonly property color fxSurface:       "#2A2318"
    readonly property color fxPrimaryText:   "#F4EED8"
    readonly property color fxSecondaryText: "#9A8F78"
    readonly property color fxRim:           "#D8CEAE"
    readonly property color fxAmber:         "#C87941"

    // ── Resolved tokens ───────────────────────────────────────────────────

    // Page background. Transparent in ambient mode so the wallpaper shows.
    readonly property color deepBg: ambient
        ? (_dark ? "black" : "white")
        : fxDeepBg

    // Card / pill fills
    readonly property color surface: ambient
        ? Theme.rgba(Theme.primaryColor, 0.20)
        : fxSurface

    // Fully opaque — for overlays and menu items where nothing may show through
    readonly property color surfaceOpaque: ambient
        ? (_dark ? "#1C1C1C" : "#FAFAFA")
        : fxSurface

    readonly property color primaryText: ambient
        ? Theme.primaryColor
        : fxPrimaryText

    readonly property color secondaryText: ambient
        ? Theme.secondaryColor
        : fxSecondaryText

    readonly property color rim: ambient
        ? Theme.rgba(Theme.primaryColor, 0.4)
        : fxRim

    readonly property color amber: ambient
        ? Theme.highlightColor
        : fxAmber

    readonly property color amberSoft: ambient
        ? Theme.rgba(Theme.highlightColor, 0.15)
        : Qt.rgba(0.784, 0.475, 0.255, 0.15)

    readonly property color amberMed: ambient
        ? Theme.rgba(Theme.highlightColor, 0.25)
        : Qt.rgba(0.784, 0.475, 0.255, 0.25)

    readonly property color amberStrong: ambient
        ? Theme.rgba(Theme.highlightColor, 0.75)
        : Qt.rgba(0.784, 0.475, 0.255, 0.75)

    // Text/icons drawn ON TOP of an amber fill — must contrast with `amber`
    readonly property color onAccent: ambient
        ? (_dark ? "black" : "white")
        : fxDeepBg

    // Opaque backing where transparency would hurt legibility (viewfinder box)
    readonly property color solidBg: ambient
        ? (_dark ? "black" : "white")
        : fxDeepBg

    // Never ambient — wrong is wrong
    readonly property color warning: "#A0403A"

    // ── Type ──────────────────────────────────────────────────────────────
    readonly property string serif: "Georgia"
}
