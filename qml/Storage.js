.import QtQuick.LocalStorage 2.0 as LS

// ── Database handle ──────────────────────────────────────────────────────────
function getDB() {
    return LS.LocalStorage.openDatabaseSync("FiatLux", "1.0", "Fiat Lux", 1000000)
}

// ── Schema ───────────────────────────────────────────────────────────────────
// schema_version 2 = relational model (cameras / lenses / stocks / rolls / shots)
// version 1 was the old embedded-lens model. Migration drops it once.
function init() {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("CREATE TABLE IF NOT EXISTS appmeta (key TEXT PRIMARY KEY, value TEXT)")

        var v = 0
        var r = tx.executeSql("SELECT value FROM appmeta WHERE key='schema_version'")
        if (r.rows.length > 0) v = parseInt(r.rows.item(0).value)

        if (v < 2) {
            tx.executeSql("DROP TABLE IF EXISTS cameras")
            tx.executeSql("DROP TABLE IF EXISTS lenses")
            tx.executeSql("DROP TABLE IF EXISTS stocks")
            tx.executeSql("DROP TABLE IF EXISTS rolls")
            tx.executeSql("DROP TABLE IF EXISTS shots")
        }

        tx.executeSql("CREATE TABLE IF NOT EXISTS cameras (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type INTEGER, mount TEXT, bodySpeeds TEXT)")
        tx.executeSql("CREATE TABLE IF NOT EXISTS lenses (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, mount TEXT, apertures TEXT, speeds TEXT)")
        tx.executeSql("CREATE TABLE IF NOT EXISTS stocks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, boxIso INTEGER)")
        tx.executeSql("CREATE TABLE IF NOT EXISTS rolls (id INTEGER PRIMARY KEY AUTOINCREMENT, stockId INTEGER, pushIso INTEGER, cameraId INTEGER, lensId INTEGER, startDate TEXT, notes TEXT, closed INTEGER)")
        tx.executeSql("CREATE TABLE IF NOT EXISTS shots (id INTEGER PRIMARY KEY AUTOINCREMENT, rollId INTEGER, timestamp TEXT, ev REAL, aperture TEXT, shutterSpeed TEXT, iso INTEGER, photoPath TEXT)")

        tx.executeSql("INSERT OR REPLACE INTO appmeta (key, value) VALUES ('schema_version', '2')")
    })
}

// ── Cameras ──────────────────────────────────────────────────────────────────
function addCamera(name, type, mount, bodySpeeds) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("INSERT INTO cameras (name, type, mount, bodySpeeds) VALUES (?,?,?,?)", [name, type, mount, bodySpeeds])
    })
}

function updateCamera(id, name, type, mount, bodySpeeds) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("UPDATE cameras SET name=?, type=?, mount=?, bodySpeeds=? WHERE id=?", [name, type, mount, bodySpeeds, id])
    })
}

function deleteCamera(id) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("DELETE FROM cameras WHERE id=?", [id])
    })
}

function loadCameras(model) {
    var db = getDB()
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT * FROM cameras ORDER BY name COLLATE NOCASE")
        model.clear()
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            model.append({ id: row.id, name: row.name, type: row.type, mount: row.mount, bodySpeeds: row.bodySpeeds })
        }
    })
}

function getCamera(id) {
    var db = getDB(), out = null
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT * FROM cameras WHERE id=?", [id])
        if (rs.rows.length > 0) {
            var row = rs.rows.item(0)
            out = { id: row.id, name: row.name, type: row.type, mount: row.mount, bodySpeeds: row.bodySpeeds }
        }
    })
    return out
}

// ── Lenses ───────────────────────────────────────────────────────────────────
function addLens(name, mount, apertures, speeds) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("INSERT INTO lenses (name, mount, apertures, speeds) VALUES (?,?,?,?)", [name, mount, apertures, speeds])
    })
}

function updateLens(id, name, mount, apertures, speeds) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("UPDATE lenses SET name=?, mount=?, apertures=?, speeds=? WHERE id=?", [name, mount, apertures, speeds, id])
    })
}

function deleteLens(id) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("DELETE FROM lenses WHERE id=?", [id])
    })
}

function loadLenses(model) {
    var db = getDB()
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT * FROM lenses ORDER BY name COLLATE NOCASE")
        model.clear()
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            model.append({ id: row.id, name: row.name, mount: row.mount, apertures: row.apertures, speeds: row.speeds })
        }
    })
}

function getLens(id) {
    var db = getDB(), out = null
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT * FROM lenses WHERE id=?", [id])
        if (rs.rows.length > 0) {
            var row = rs.rows.item(0)
            out = { id: row.id, name: row.name, mount: row.mount, apertures: row.apertures, speeds: row.speeds }
        }
    })
    return out
}

// Lenses compatible with a given mount — returns a plain array (for pickers)
function lensesForMount(mount) {
    var db = getDB(), arr = []
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT * FROM lenses WHERE mount=? ORDER BY name COLLATE NOCASE", [mount])
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            arr.push({ id: row.id, name: row.name, mount: row.mount, apertures: row.apertures, speeds: row.speeds })
        }
    })
    return arr
}

// Distinct mounts across cameras and lenses — for autocomplete
function mounts() {
    var db = getDB(), arr = []
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT mount FROM cameras WHERE mount<>'' UNION SELECT mount FROM lenses WHERE mount<>'' ORDER BY mount COLLATE NOCASE")
        for (var i = 0; i < rs.rows.length; i++) arr.push(rs.rows.item(i).mount)
    })
    return arr
}

// ── Film stocks ──────────────────────────────────────────────────────────────
function addStock(name, boxIso) {
    var db = getDB(), newId = -1
    db.transaction(function(tx) {
        var rs = tx.executeSql("INSERT INTO stocks (name, boxIso) VALUES (?,?)", [name, boxIso])
        newId = parseInt(rs.insertId)
    })
    return newId
}

function updateStock(id, name, boxIso) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("UPDATE stocks SET name=?, boxIso=? WHERE id=?", [name, boxIso, id])
    })
}

function deleteStock(id) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("DELETE FROM stocks WHERE id=?", [id])
    })
}

function loadStocks(model) {
    var db = getDB()
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT * FROM stocks ORDER BY name COLLATE NOCASE")
        model.clear()
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            model.append({ id: row.id, name: row.name, boxIso: row.boxIso })
        }
    })
}

function getStock(id) {
    var db = getDB(), out = null
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT * FROM stocks WHERE id=?", [id])
        if (rs.rows.length > 0) {
            var row = rs.rows.item(0)
            out = { id: row.id, name: row.name, boxIso: row.boxIso }
        }
    })
    return out
}

// ── Rolls ────────────────────────────────────────────────────────────────────
function addRoll(stockId, pushIso, cameraId, lensId, startDate, notes) {
    var db = getDB(), newId = -1
    db.transaction(function(tx) {
        var rs = tx.executeSql("INSERT INTO rolls (stockId, pushIso, cameraId, lensId, startDate, notes, closed) VALUES (?,?,?,?,?,?,0)",
                               [stockId, pushIso, cameraId, lensId, startDate, notes])
        newId = parseInt(rs.insertId)
    })
    return newId
}

function updateRoll(id, stockId, pushIso, cameraId, lensId, notes) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("UPDATE rolls SET stockId=?, pushIso=?, cameraId=?, lensId=?, notes=? WHERE id=?",
                      [stockId, pushIso, cameraId, lensId, notes, id])
    })
}

function closeRoll(id) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("UPDATE rolls SET closed=1 WHERE id=?", [id])
    })
}

function deleteRoll(id) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("DELETE FROM shots WHERE rollId=?", [id])
        tx.executeSql("DELETE FROM rolls WHERE id=?", [id])
    })
}

// Load open rolls with joined display names + shot count
function loadRolls(model, includeClosed) {
    var db = getDB()
    var where = includeClosed ? "" : "WHERE r.closed=0 "
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT r.*, s.name AS stockName, c.name AS cameraName, l.name AS lensName, (SELECT COUNT(*) FROM shots WHERE rollId=r.id) AS shotCount FROM rolls r LEFT JOIN stocks s ON r.stockId=s.id LEFT JOIN cameras c ON r.cameraId=c.id LEFT JOIN lenses l ON r.lensId=l.id " + where + "ORDER BY r.startDate DESC")
        model.clear()
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            model.append({
                id: row.id, stockId: row.stockId, pushIso: row.pushIso,
                cameraId: row.cameraId, lensId: row.lensId, startDate: row.startDate,
                notes: row.notes || "", closed: row.closed,
                stockName: row.stockName || "", cameraName: row.cameraName || "",
                lensName: row.lensName || "", shotCount: row.shotCount
            })
        }
    })
}

function getRoll(id) {
    var db = getDB(), out = null
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT r.*, s.name AS stockName, s.boxIso AS boxIso, c.name AS cameraName, c.type AS cameraType, c.mount AS mount, c.bodySpeeds AS bodySpeeds, l.name AS lensName, l.apertures AS apertures, l.speeds AS lensSpeeds FROM rolls r LEFT JOIN stocks s ON r.stockId=s.id LEFT JOIN cameras c ON r.cameraId=c.id LEFT JOIN lenses l ON r.lensId=l.id WHERE r.id=?", [id])
        if (rs.rows.length > 0) {
            var row = rs.rows.item(0)
            out = {
                id: row.id, stockId: row.stockId, pushIso: row.pushIso,
                cameraId: row.cameraId, lensId: row.lensId, startDate: row.startDate,
                notes: row.notes || "", stockName: row.stockName || "", boxIso: row.boxIso,
                cameraName: row.cameraName || "", cameraType: row.cameraType,
                mount: row.mount || "", bodySpeeds: row.bodySpeeds || "",
                lensName: row.lensName || "", apertures: row.apertures || "", lensSpeeds: row.lensSpeeds || ""
            }
        }
    })
    return out
}

// ── Shots ────────────────────────────────────────────────────────────────────
function addShot(rollId, timestamp, ev, aperture, shutterSpeed, iso, photoPath) {
    var db = getDB(), newId = -1
    db.transaction(function(tx) {
        var rs = tx.executeSql("INSERT INTO shots (rollId, timestamp, ev, aperture, shutterSpeed, iso, photoPath) VALUES (?,?,?,?,?,?,?)",
                               [rollId, timestamp, ev, aperture, shutterSpeed, iso, photoPath])
        newId = parseInt(rs.insertId)
    })
    return newId
}

function deleteShot(id) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("DELETE FROM shots WHERE id=?", [id])
    })
}

function loadShots(model, rollId) {
    var db = getDB()
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT * FROM shots WHERE rollId=? ORDER BY id ASC", [rollId])
        model.clear()
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            model.append({
                id: row.id, rollId: row.rollId, timestamp: row.timestamp,
                ev: row.ev, aperture: row.aperture, shutterSpeed: row.shutterSpeed,
                iso: row.iso, photoPath: row.photoPath || "", frame: i + 1
            })
        }
    })
}

function shotCountForRoll(rollId) {
    var db = getDB(), n = 0
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT COUNT(*) AS c FROM shots WHERE rollId=?", [rollId])
        n = rs.rows.item(0).c
    })
    return n
}
