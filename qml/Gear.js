.pragma library

// The values a camera can have, and the arithmetic on them. Shared by the
// meter, the camera and lens forms and the plate dialogs, so a speed means
// the same thing everywhere.
//
// Speeds are stored as text, fastest first, B last:  1/500,1/250,...,1",B
// Apertures are stored as text, widest first:        2.8,4,5.6,...,22
// Whole seconds are written with a plain double quote: 1" 2" 30"

// ---- the plate, as printed on the back of the camera ----
//
// No 1/8000. The groups are only for reading; any value can be chosen.

var speedGroups = [
    { title: "long", values: ["B", "30\"", "15\"", "8\"", "4\"", "2\"", "1\"", "1/2"] },
    { title: "slow", values: ["1/4", "1/5", "1/8", "1/10", "1/15", "1/25", "1/30", "1/50"] },
    { title: "fast", values: ["1/60", "1/100", "1/125", "1/200", "1/250", "1/300", "1/400", "1/500",
                              "1/1000", "1/2000", "1/4000"] }
]

// Doubling series, from the 1960s on: Pentax MX, Nikon FM, Yashica Mat.
var modernSpeeds = ["1/1000", "1/500", "1/250", "1/125", "1/60", "1/30", "1/15", "1/8", "1/4", "1/2", "1\"", "B"]
// The continental series of older Compur and Prontor leaf shutters.
var classicSpeeds = ["1/500", "1/250", "1/100", "1/50", "1/25", "1/10", "1/5", "1/2", "1\"", "B"]

var apertureGroups = [
    { title: "wide", values: ["1", "1.2", "1.4", "1.7", "1.8", "2"] },
    { title: "middle", values: ["2.8", "3.5", "4", "4.5", "5.6", "6.3", "8"] },
    { title: "small", values: ["11", "16", "22", "32", "45", "64"] }
]

var fullStops = ["1", "1.4", "2", "2.8", "4", "5.6", "8", "11", "16", "22", "32", "45", "64"]

var isoGroups = [
    { title: "slow", values: ["25", "50", "64", "80", "100", "125", "160"] },
    { title: "medium", values: ["200", "250", "320", "400", "500", "640", "800"] },
    { title: "fast", values: ["1000", "1250", "1600", "3200", "6400"] }
]

// Common mounts, for the mount list. `also` is only searched, never shown.
var mounts = [
    { name: "Canon FD", note: "breech-lock", also: "fd fl" },
    { name: "Canon FL", note: "", also: "fl" },
    { name: "Contax/Yashica", note: "C/Y", also: "cy c/y yashica contax" },
    { name: "Exakta", note: "", also: "ihagee" },
    { name: "Hasselblad V", note: "500 series", also: "500c 500cm 503" },
    { name: "Konica AR", note: "", also: "ar" },
    { name: "Leica M", note: "", also: "m-mount bayonet" },
    { name: "Leica M39", note: "screw mount, LTM", also: "ltm l39 screw" },
    { name: "M42", note: "Praktica, Zenit, Spotmatic", also: "screw pentax praktica zenit" },
    { name: "Mamiya 645", note: "", also: "645" },
    { name: "Mamiya RB67", note: "", also: "rb" },
    { name: "Mamiya RZ67", note: "", also: "rz" },
    { name: "Minolta SR", note: "MC / MD", also: "md mc rokkor" },
    { name: "Nikon F", note: "", also: "ai ais nikkor" },
    { name: "Olympus OM", note: "", also: "om zuiko" },
    { name: "Pentax 67", note: "", also: "6x7" },
    { name: "Pentax K", note: "PK", also: "k-mount kmount pk" },
    { name: "Praktica B", note: "", also: "pb" },
    { name: "Rollei QBM", note: "", also: "qbm voigtlander" }
]

// ---- speeds ----

// Seconds, or null for B.
function parseSpeed(s) {
    if (s === undefined || s === null) return NaN
    s = ("" + s).trim()
    if (s === "B") return null
    if (s.indexOf("/") !== -1) {
        var p = s.split("/")
        return parseFloat(p[0]) / parseFloat(p[1])
    }
    return parseFloat(s.replace("\"", ""))
}

// Whatever was typed, as a speed, or "" if it is not one.
//   1/320  320  -> 1/320        3  3s  3"  -> 3"        b -> B
// A bare number above 1 is read as a fraction when it is one of the usual
// denominators' neighbours (people type 320 for 1/320) and as seconds when
// it ends in s or a quote.
function normaliseSpeed(text) {
    var s = ("" + text).trim().replace(/″/g, "\"").replace(/′′/g, "\"")
    if (s.length === 0) return ""
    if (s === "b" || s === "B") return "B"
    var m = s.match(/^1\s*\/\s*(\d+(\.\d+)?)$/)
    if (m) {
        var d = parseFloat(m[1])
        if (!(d > 0)) return ""
        if (d <= 1) return "1\""
        return "1/" + trimNumber(d)
    }
    m = s.match(/^(\d+(\.\d+)?)\s*(s|sec|"|'')$/i)
    if (m) {
        var sec = parseFloat(m[1])
        return sec > 0 ? trimNumber(sec) + "\"" : ""
    }
    m = s.match(/^(\d+(\.\d+)?)$/)
    if (m) {
        var n = parseFloat(m[1])
        if (!(n > 0)) return ""
        if (n <= 1) return n === 1 ? "1\"" : "1/" + trimNumber(Math.round(1 / n))
        // A bare 2 or 4 is more likely seconds than 1/2 s written oddly,
        // anything from 8 up a fraction.
        return n < 8 ? trimNumber(n) + "\"" : "1/" + trimNumber(n)
    }
    return ""
}

function trimNumber(n) {
    var r = Math.round(n * 10) / 10
    return r % 1 === 0 ? r.toFixed(0) : r.toFixed(1)
}

// Longest first, B leading: the order on the plate.
function speedsForPlate(list) {
    return unique(list).sort(function(a, b) {
        var ta = parseSpeed(a), tb = parseSpeed(b)
        if (ta === null) return -1
        if (tb === null) return 1
        return tb - ta
    })
}

// Fastest first, B last: the order in the database.
function speedsForStorage(list) {
    return unique(list).sort(function(a, b) {
        var ta = parseSpeed(a), tb = parseSpeed(b)
        if (ta === null) return 1
        if (tb === null) return -1
        return ta - tb
    })
}

function speedGroupIndex(s) {
    var t = parseSpeed(s)
    if (t === null || t >= 0.5) return 0
    if (t >= 1 / 50) return 1
    return 2
}

// "1/300 – 1", B" and "9 speeds"
function speedSummary(list) {
    if (!list || list.length === 0) return ""
    var timed = speedsForStorage(list).filter(function(s) { return s !== "B" })
    var hasB = list.indexOf("B") !== -1
    var range = timed.length === 0 ? "" : timed.length === 1 ? timed[0]
              : timed[0] + " – " + timed[timed.length - 1]
    if (hasB) range = range.length > 0 ? range + ", B" : "B"
    return range
}

function speedCount(list) {
    var n = list ? list.length : 0
    return n === 1 ? "1 speed" : n + " speeds"
}

// ---- apertures ----

function normaliseAperture(text) {
    var s = ("" + text).trim().replace(/^f\s*\/?\s*/i, "").replace(",", ".")
    var n = parseFloat(s)
    if (!(n > 0) || n > 256 || !/^\d+(\.\d+)?$/.test(s)) return ""
    return trimNumber(n)
}

function sortApertures(list) {
    return unique(list).sort(function(a, b) { return parseFloat(a) - parseFloat(b) })
}

function apertureGroupIndex(a) {
    var n = parseFloat(a)
    if (n < 2.5) return 0
    if (n < 9.5) return 1
    return 2
}

// "f/3.5 – f/22" and "7 apertures"
function apertureSummary(list) {
    if (!list || list.length === 0) return ""
    var s = sortApertures(list)
    return s.length === 1 ? "f/" + s[0] : "f/" + s[0] + " – f/" + s[s.length - 1]
}

function apertureCount(list) {
    var n = list ? list.length : 0
    return n === 1 ? "1 aperture" : n + " apertures"
}

// The full stops from the widest chosen aperture down to f/22, added to what
// is already chosen.
function fillFullStops(list) {
    var s = sortApertures(list)
    if (s.length === 0) return ["2.8", "4", "5.6", "8", "11", "16", "22"]
    var widest = parseFloat(s[0])
    var out = s.slice()
    for (var i = 0; i < fullStops.length; i++) {
        var v = parseFloat(fullStops[i])
        if (v > widest + 0.05 && v <= 22 && out.indexOf(fullStops[i]) === -1) out.push(fullStops[i])
    }
    return sortApertures(out)
}

// ---- ISO ----

function normaliseIso(text) {
    var n = parseInt(("" + text).trim().replace(/^iso\s*/i, ""), 10)
    return n > 0 && n < 100000 ? "" + n : ""
}

// ---- the plate's groups with anything unusual folded in ----
//
// A value that is not on the printed plate (1/320, f/2.4, ISO 12) goes into
// the group it belongs to, in its place, so the plate always shows everything
// that is chosen.

function mergedGroups(kind, selected) {
    var master = kind === "speeds" ? speedGroups : kind === "apertures" ? apertureGroups : isoGroups
    var out = []
    var known = {}
    var g, i
    for (g = 0; g < master.length; g++) {
        out.push({ title: master[g].title, values: master[g].values.slice() })
        for (i = 0; i < master[g].values.length; i++) known[master[g].values[i]] = true
    }
    for (i = 0; i < (selected || []).length; i++) {
        var v = selected[i]
        if (known[v]) continue
        known[v] = true
        var k = kind === "speeds" ? speedGroupIndex(v) : kind === "apertures" ? apertureGroupIndex(v)
              : (parseInt(v) < 200 ? 0 : parseInt(v) < 1000 ? 1 : 2)
        out[k].values.push(v)
    }
    for (g = 0; g < out.length; g++) {
        if (kind === "speeds") out[g].values = speedsForPlate(out[g].values)
        else if (kind === "apertures") out[g].values = sortApertures(out[g].values)
        else out[g].values = unique(out[g].values).sort(function(a, b) { return parseInt(a) - parseInt(b) })
    }
    return out
}

// Rows for a group: at most four to a row, spread as evenly as the count
// allows, so a row of three is as wide as a row of four and nothing is left
// alone on a line.
function rowsFor(values) {
    var n = values.length
    if (n === 0) return []
    var rows = Math.ceil(n / 4)
    var base = Math.floor(n / rows)
    var extra = n % rows
    var out = []
    var at = 0
    for (var r = 0; r < rows; r++) {
        var count = base + (r < extra ? 1 : 0)
        out.push(values.slice(at, at + count))
        at += count
    }
    return out
}

// ---- small things ----

function unique(list) {
    var seen = {}
    var out = []
    for (var i = 0; i < (list || []).length; i++) {
        var v = list[i]
        if (v === undefined || v === null || v === "" || seen[v]) continue
        seen[v] = true
        out.push(v)
    }
    return out
}

function splitList(text) {
    if (!text || ("" + text).length === 0) return []
    return ("" + text).split(",").filter(function(v) { return v.length > 0 })
}

// Stops in thirds: 0, ⅓, ⅔, 1, 1⅓ ...
function thirds(x) {
    var r = Math.round(Math.abs(x) * 3)
    if (r === 0) return "0"
    var whole = Math.floor(r / 3), frac = r % 3
    var f = frac === 1 ? "⅓" : frac === 2 ? "⅔" : ""
    return (whole > 0 ? "" + whole : "") + f
}

function formatSeconds(t) {
    if (!(t > 0)) return "-"
    if (t < 0.75) return "1/" + Math.round(1 / t)
    if (t < 10) return trimNumber(t) + "\""
    if (t < 90) return Math.round(t) + "\""
    return Math.round(t / 60) + " min"
}
