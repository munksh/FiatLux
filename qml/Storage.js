.import QtQuick.LocalStorage 2.0 as Sql

function db() {
    return Sql.LocalStorage.openDatabaseSync("FiatLux", "1.0", "Fiat Lux camera database", 1000000)
}

function init() {
    db().transaction(function(tx) {
        tx.executeSql('CREATE TABLE IF NOT EXISTS cameras (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, film TEXT, iso INTEGER, type INTEGER, bodySpeeds TEXT, lenses TEXT)')
    })
}

function addCamera(name, film, iso, type, bodySpeeds, lenses) {
    var id = -1
    db().transaction(function(tx) {
        var result = tx.executeSql('INSERT INTO cameras (name, film, iso, type, bodySpeeds, lenses) VALUES (?, ?, ?, ?, ?, ?)', [name, film, iso, type, bodySpeeds, lenses])
        id = result.insertId
    })
    return id
}

function loadCameras(model) {
    model.clear()
    db().transaction(function(tx) {
        var rs = tx.executeSql('SELECT * FROM cameras ORDER BY name')
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            model.append({
                "id": row.id,
                "name": row.name,
                "film": row.film,
                "iso": row.iso,
                "type": row.type,
                "bodySpeeds": row.bodySpeeds,
                "lenses": row.lenses
            })
        }
    })
}

function deleteCamera(id) {
    db().transaction(function(tx) {
        tx.executeSql('DELETE FROM cameras WHERE id = ?', [id])
    })
}
