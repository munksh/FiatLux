pragma Singleton

import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// Fiat colours — the family standard. Two palettes behind one set of names,
// switched by a single boolean that is remembered between runs.
//
//   ambient = true   the user's ambience via Theme.*. No background is
//                    painted anywhere; the wallpaper is the background.
//   ambient = false  Fiat colours. The app paints its own light background
//                    and uses the family palette.
//
// This replaces the old darkroom palette (fxDeepBg and friends). That palette
// predated ambience-first: `deepBg` returned an opaque black or white even in
// ambient mode, so the app painted a plate over the wallpaper on nineteen
// separate items and on the cover. Fiat Lux was never actually ambient.
//
// The bottom half of this file is a compatibility shelf: every name the old
// theme exported still resolves, so the app runs the moment this file lands
// and the pages can be migrated one at a time.

QtObject {
    id: t

    // ---- the switch, remembered between runs ----
    //
    // The key names the PACKAGE, and the package is about to become
    // harbour-fiatlux. Changing it now costs one boolean, once.
    property ConfigurationValue ambientConfig: ConfigurationValue {
        key: "/apps/harbour-fiatlux/ambient"
        defaultValue: true
    }
    readonly property bool ambient: ambientConfig.value
    function setAmbient(on) { ambientConfig.value = on }

    // Fiat colours are a light scheme, so dark is false there.
    readonly property bool dark: ambient ? (Theme.colorScheme === Theme.LightOnDark) : false

    // ---- type ----
    readonly property string serif: "Georgia"

    // Six places in the app ask for this and the old singleton never defined
    // it, so they have been rendering in whatever Qt fell back to. "monospace"
    // is a fontconfig alias and resolves on Sailfish; verify it once with the
    // Xyzzy trick before trusting it. The design system would rather the big
    // exposure figures used `serif` — a grotesque numeral under a serif
    // wordmark reads as two unrelated typefaces.
    readonly property string mono: "monospace"

    // ---- the notch ----
    //
    // Silica's own PageHeader clears the cutout. Ours do not, because they are
    // ours -- and on the Jolla Phone (2026) that puts the top of a capital
    // letter, and the left end of a long right-aligned title, straight into
    // the hole. So every header in this app starts this far down.
    //
    // Read from the platform when the platform will say. Asking a QObject for
    // a property it does not have returns undefined rather than throwing, so
    // the probe is safe -- but the fallback has to be a real number.
    function cutoutHeight() {
        if (typeof Screen === "undefined" || Screen === null) return -1
        var c = Screen.topCutout
        if (c === undefined || c === null) return -1
        if (typeof c === "number") return c
        if (c.height !== undefined) return c.height
        return -1
    }

    readonly property real headerTopInsetFallback: Theme.paddingLarge * 1.5

    readonly property real headerTopInset: {
        var c = cutoutHeight()
        return c >= 0 ? c + Theme.paddingMedium : headerTopInsetFallback
    }

    // Where the system's own indicators sit. Anything of ours that belongs on
    // that line (the wordmark, Cancel, Save) is centred on it rather than
    // given a top margin. This is the known-good number from Fiat Mos, where
    // two attempts at deriving it from the cutout both walked it up the screen
    // for no reason. Bigger moves them down, smaller moves them up.
    readonly property real statusRowCenter: Theme.itemSizeLarge / 2

    // ---- text and accent ----
    readonly property color primaryText:   ambient ? Theme.primaryColor   : "#1A1A1A"
    readonly property color secondaryText: ambient ? Theme.secondaryColor : Qt.rgba(0.10, 0.10, 0.10, 0.55)

    // Fiat Lux's accent: burnt amber, the safelight in a darkroom. It is the
    // one colour that differs from the rest of the family, and it survives the
    // move to the light paper unchanged.
    readonly property color accent: ambient ? Theme.highlightColor : "#C87941"

    // ---- the shared paper ----
    readonly property color backgroundHigh: "#F2EFE8"
    readonly property color backgroundLow:  "#D8D2C6"

    readonly property color card: ambient
        ? (dark ? Qt.rgba(0.08, 0.08, 0.08, 1.0) : Qt.rgba(0.96, 0.96, 0.96, 1.0))
        : "#F5F5F5"
    readonly property color cardBorder:   Theme.rgba(primaryText, 0.45)
    readonly property color innerBorder:  Theme.rgba(primaryText, 0.22)
    readonly property color recessFill:   Theme.rgba(primaryText, 0.05)
    readonly property color recessBorder: Theme.rgba(primaryText, 0.16)
    readonly property real cardRadius: Theme.paddingLarge * 2
    readonly property int cardBorderWidth: 2

    // ---- pills ----
    readonly property color pillFill:         Theme.rgba(primaryText, 0.15)
    readonly property color pillBorder:       Theme.rgba(primaryText, 0.55)
    readonly property color pillFillActive:   Theme.rgba(accent, 0.15)
    readonly property color pillBorderActive: Theme.rgba(accent, 0.45)

    // ---- meaning, never decoration ----
    //
    // Fiat Lux has one verdict: the exposure cannot be made. The calculated
    // time falls outside every speed this camera actually has, so no pairing
    // of the dials will get it right and the reading is advice, not a setting.
    //
    // There is deliberately no amber "near" from the family's semantic table.
    // Amber is this app's accent, and the family rule is that an accent must
    // not collide with a semantic colour -- an amber warning under an amber
    // accent says nothing. There is no green "good" either: being in range is
    // the normal case, and the normal case does not need a colour.
    readonly property color outOfRange: dark ? "#A0403A" : "#8A2B25"

    // Unfilled dots, ring tracks, empty cells, anything absent.
    readonly property color dotIdle: Theme.rgba(primaryText, 0.22)

    // The viewfinder, and the ONE fixed dark colour in the app. It stands in
    // for a camera feed, so it follows neither the ambience nor Fiat colours
    // -- a viewfinder that went cream on a light ambience would be a bug.
    readonly property color viewfinderBg: "#111111"

    // Readable mark drawn on top of an accent fill.
    //
    // Measured, not guessed from the colour scheme: an ambience can pair a
    // light scheme with a dark highlight or the other way round. Perceived
    // luminance of the accent decides whether the mark on top is dark or
    // light. A function, not a chain of readonly bindings -- the chained
    // version came out undefined on the device, and an undefined colour does
    // not shout, it silently renders black.
    function markOn(c) {
        if (c === undefined || c === null) return "#F5F5F5"
        return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 0.55 ? "#1A1A1A" : "#F5F5F5"
    }

    // ---- the maker's mark ----
    //
    // Taupe, and a FIXED value: this one deliberately does not follow the
    // ambience, for the same reason the launcher icon does not. It is
    // Munkstolen's colour, not the app's, and a signature that changed colour
    // with the wallpaper would not be a signature.
    readonly property color makerMark: "#7E7566"

    // The wash under a pressed row or menu item. Silica would use the
    // ambience highlight here, which bleeds through Fiat colours.
    readonly property color highlightWash: Theme.rgba(accent, 0.15)

    // ---- Silica's own chrome ----
    //
    // Menus, pull-down drawers, ComboBox values, TextField labels and
    // underlines, sliders, selection: none of these takes a colour from us.
    // They read Theme.* directly, which is the ambience, which is why they
    // stay ambience-coloured under Fiat colours no matter how many `color:`
    // lines you add to individual items.
    //
    // Silica's answer is `palette` -- colour roles that hang off an item and
    // are INHERITED by its children. Set it once on the ApplicationWindow and
    // every Silica control below it follows.
    //
    // Written defensively on purpose. A missing property assigned in a QML
    // binding is a load-time error and the whole page dies; assigned from
    // JavaScript it is a no-op, and the try/catch takes the rest.
    function applyPalette(item) {
        if (item === null || item === undefined) return
        var p = item.palette
        if (p === undefined || p === null) return
        try { p.colorScheme = ambient ? Theme.colorScheme : Theme.DarkOnLight } catch (e) { }
        try { p.primaryColor = primaryText } catch (e) { }
        try { p.secondaryColor = secondaryText } catch (e) { }
        try { p.highlightColor = accent } catch (e) { }
        try { p.secondaryHighlightColor = Theme.rgba(accent, 0.6) } catch (e) { }
        try { p.highlightBackgroundColor = Theme.rgba(accent, 0.3) } catch (e) { }
        try { p.errorColor = outOfRange } catch (e) { }
        try { p.highlightDimmerColor = ambient ? Theme.highlightDimmerColor : backgroundLow } catch (e) { }
        try { p.overlayBackgroundColor = ambient ? Theme.overlayBackgroundColor : backgroundHigh } catch (e) { }
    }

    // ─────────────────────────────────────────────────────────────────────
    // COMPATIBILITY SHELF — the old theme's names, so nothing breaks today.
    //
    // Delete each one as its last caller is migrated. When this block is
    // empty the retrofit is done, and that is a better progress bar than a
    // checklist.
    // ─────────────────────────────────────────────────────────────────────

    // Was an opaque plate that cancelled the ambience. Now a faint wash, which
    // is what the ChooserRow and the pill fills actually wanted. Page
    // backgrounds that use this must move to the conditional gradient instead.
    readonly property color deepBg: recessFill

    readonly property color surface: card
    readonly property color surfaceOpaque: card
    readonly property color rim: cardBorder
    readonly property color amber: accent
    readonly property color amberSoft: Theme.rgba(accent, 0.15)
    readonly property color amberMed: Theme.rgba(accent, 0.25)
    readonly property color amberStrong: Theme.rgba(accent, 0.75)
    readonly property color onAccent: markOn(accent)
    readonly property color solidBg: viewfinderBg
    readonly property color warning: outOfRange
}
