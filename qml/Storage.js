.import QtQuick.LocalStorage 2.0 as LS

// ── Database handle ──────────────────────────────────────────────────────────
function getDB() {
    return LS.LocalStorage.openDatabaseSync("FiatLux", "1.0", "Fiat Lux", 1000000)
}

// ── Schema ───────────────────────────────────────────────────────────────────
// schema_version 2 = relational model (cameras / lenses / stocks / rolls / shots)
// version 1 was the old embedded-lens model. Migration drops it once.
// schema_version 3 = cameras.apertures (a fixed lens belongs to its camera)
// and stocks.favourite. Added in place: nothing a version 2 user saved is lost.
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

        if (v === 2) {
            // try/catch: a column that is already there must not take the
            // whole transaction, and with it the database, down.
            try { tx.executeSql("ALTER TABLE cameras ADD COLUMN apertures TEXT") } catch (e1) { }
            try { tx.executeSql("ALTER TABLE stocks ADD COLUMN favourite INTEGER DEFAULT 0") } catch (e2) { }
            // A fixed-lens camera used to need a lens of the same mount. Move
            // that lens's apertures, and its speeds if the camera had none,
            // onto the camera itself.
            tx.executeSql("UPDATE cameras SET apertures=(SELECT l.apertures FROM lenses l WHERE l.mount=cameras.mount LIMIT 1), bodySpeeds=CASE WHEN IFNULL(bodySpeeds,'')='' THEN IFNULL((SELECT l.speeds FROM lenses l WHERE l.mount=cameras.mount LIMIT 1),'') ELSE bodySpeeds END WHERE type=0 AND IFNULL(apertures,'')=''")
        }

        tx.executeSql("CREATE TABLE IF NOT EXISTS cameras (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type INTEGER, mount TEXT, bodySpeeds TEXT, apertures TEXT)")
        tx.executeSql("CREATE TABLE IF NOT EXISTS lenses (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, mount TEXT, apertures TEXT, speeds TEXT)")
        tx.executeSql("CREATE TABLE IF NOT EXISTS stocks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, boxIso INTEGER, favourite INTEGER DEFAULT 0)")
        tx.executeSql("CREATE TABLE IF NOT EXISTS rolls (id INTEGER PRIMARY KEY AUTOINCREMENT, stockId INTEGER, pushIso INTEGER, cameraId INTEGER, lensId INTEGER, startDate TEXT, notes TEXT, closed INTEGER)")
        tx.executeSql("CREATE TABLE IF NOT EXISTS shots (id INTEGER PRIMARY KEY AUTOINCREMENT, rollId INTEGER, timestamp TEXT, ev REAL, aperture TEXT, shutterSpeed TEXT, iso INTEGER, photoPath TEXT)")

        tx.executeSql("INSERT OR REPLACE INTO appmeta (key, value) VALUES ('schema_version', '3')")
    })
}

// ── Cameras ──────────────────────────────────────────────────────────────────
// type: 0 fixed lens, 1 interchangeable with the shutter in the body,
// 2 interchangeable with a shutter in each lens. bodySpeeds is used by 0 and 1,
// apertures by 0 only; the rest live on the lenses.
function addCamera(name, type, mount, bodySpeeds, apertures) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("INSERT INTO cameras (name, type, mount, bodySpeeds, apertures) VALUES (?,?,?,?,?)", [name, type, mount || "", bodySpeeds || "", apertures || ""])
    })
}

function updateCamera(id, name, type, mount, bodySpeeds, apertures) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("UPDATE cameras SET name=?, type=?, mount=?, bodySpeeds=?, apertures=? WHERE id=?", [name, type, mount || "", bodySpeeds || "", apertures || "", id])
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
            model.append({ id: row.id, name: row.name, type: row.type, mount: row.mount || "", bodySpeeds: row.bodySpeeds || "", apertures: row.apertures || "" })
        }
    })
}

function getCamera(id) {
    var db = getDB(), out = null
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT * FROM cameras WHERE id=?", [id])
        if (rs.rows.length > 0) {
            var row = rs.rows.item(0)
            out = { id: row.id, name: row.name, type: row.type, mount: row.mount || "", bodySpeeds: row.bodySpeeds || "", apertures: row.apertures || "" }
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

// Find a stock by name, or make it. The film catalogue is not in the database;
// a catalogue film becomes a row the first time it is loaded or starred.
function ensureStock(name, boxIso) {
    var db = getDB(), id = -1
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT id FROM stocks WHERE name=? COLLATE NOCASE", [name])
        if (rs.rows.length > 0) {
            id = rs.rows.item(0).id
        } else {
            var ins = tx.executeSql("INSERT INTO stocks (name, boxIso, favourite) VALUES (?,?,0)", [name, boxIso])
            id = parseInt(ins.insertId)
        }
    })
    return id
}

function setStockFavourite(id, on) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("UPDATE stocks SET favourite=? WHERE id=?", [on ? 1 : 0, id])
    })
}

// Every film the picker can offer: the user's own stocks, then catalogue
// films not already among them, sorted by name. lastUsed is the start date of
// the most recent roll of it, or "".
function filmsForPicker(catalogue) {
    var db = getDB(), out = [], seen = {}
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT s.id, s.name, s.boxIso, IFNULL(s.favourite,0) AS favourite, IFNULL((SELECT MAX(r.startDate) FROM rolls r WHERE r.stockId=s.id),'') AS lastUsed FROM stocks s")
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            out.push({ id: row.id, name: row.name, boxIso: row.boxIso,
                       favourite: row.favourite === 1, lastUsed: row.lastUsed })
            seen[row.name.toLowerCase()] = true
        }
    })
    for (var j = 0; j < catalogue.length; j++) {
        var c = catalogue[j]
        if (seen[c.name.toLowerCase()]) continue
        out.push({ id: -1, name: c.name, boxIso: c.iso, favourite: false, lastUsed: "" })
    }
    out.sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 })
    return out
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

// The film in a camera right now: its most recent open roll, or -1.
function openRollForCamera(cameraId) {
    var db = getDB(), id = -1
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT id FROM rolls WHERE cameraId=? AND IFNULL(closed,0)=0 ORDER BY startDate DESC LIMIT 1", [cameraId])
        if (rs.rows.length > 0) id = rs.rows.item(0).id
    })
    return id
}

// Loading a film closes whatever was in that camera before.
function closeRollsForCamera(cameraId) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("UPDATE rolls SET closed=1 WHERE cameraId=? AND IFNULL(closed,0)=0", [cameraId])
    })
}

// The lens on the camera for this roll, chosen on the meter.
function setRollLens(id, lensId) {
    var db = getDB()
    db.transaction(function(tx) {
        tx.executeSql("UPDATE rolls SET lensId=? WHERE id=?", [lensId, id])
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
        var rs = tx.executeSql("SELECT r.*, s.name AS stockName, s.boxIso AS boxIso, c.name AS cameraName, c.type AS cameraType, c.mount AS mount, c.bodySpeeds AS bodySpeeds, c.apertures AS cameraApertures, l.name AS lensName, l.apertures AS apertures, l.speeds AS lensSpeeds FROM rolls r LEFT JOIN stocks s ON r.stockId=s.id LEFT JOIN cameras c ON r.cameraId=c.id LEFT JOIN lenses l ON r.lensId=l.id WHERE r.id=?", [id])
        if (rs.rows.length > 0) {
            var row = rs.rows.item(0)
            out = {
                id: row.id, stockId: row.stockId, pushIso: row.pushIso,
                cameraId: row.cameraId, lensId: row.lensId, startDate: row.startDate,
                notes: row.notes || "", stockName: row.stockName || "", boxIso: row.boxIso,
                cameraName: row.cameraName || "", cameraType: row.cameraType,
                mount: row.mount || "", bodySpeeds: row.bodySpeeds || "",
                cameraApertures: row.cameraApertures || "",
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

// Every frame since a moment (an ISO time, as the shots are stored), with the
// roll, camera and film it belongs to. For the history page.
function shotsSince(iso) {
    var db = getDB(), out = []
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT s.timestamp AS timestamp, s.rollId AS rollId, r.closed AS closed, c.name AS cameraName, st.name AS stockName FROM shots s LEFT JOIN rolls r ON s.rollId=r.id LEFT JOIN cameras c ON r.cameraId=c.id LEFT JOIN stocks st ON r.stockId=st.id WHERE s.timestamp >= ? ORDER BY s.timestamp ASC", [iso])
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            out.push({ timestamp: row.timestamp, rollId: row.rollId, closed: row.closed ? 1 : 0,
                       cameraName: row.cameraName || "", stockName: row.stockName || "" })
        }
    })
    return out
}
function shotCountForRoll(rollId) {
    var db = getDB(), n = 0
    db.transaction(function(tx) {
        var rs = tx.executeSql("SELECT COUNT(*) AS c FROM shots WHERE rollId=?", [rollId])
        n = rs.rows.item(0).c
    })
    return n
}
