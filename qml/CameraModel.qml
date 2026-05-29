import QtQuick 2.0

ListModel {
    id: cameraModel

    function addCamera(name, film, iso, lens, apertures) {
        append({
            "name": name,
            "film": film,
            "iso": iso,
            "lens": lens,
            "apertures": apertures.join(",")
        })
    }
}
