#include "exposureprobe.h"

#include <QCamera>
#include <QCameraExposure>
#include <QCameraInfo>
#include <QStringList>
#include <QDebug>

ExposureProbe::ExposureProbe(QObject *parent)
    : QObject(parent), m_camera(0)
{
}

ExposureProbe::~ExposureProbe()
{
    delete m_camera;
}

static QString realList(const QList<qreal> &v, bool continuous)
{
    if (v.isEmpty())
        return QStringLiteral("EMPTY");
    QStringList s;
    for (int i = 0; i < v.size(); ++i)
        s << QString::number(v.at(i));
    return s.join(QStringLiteral(", "))
         + (continuous ? QStringLiteral("  (continuous)")
                       : QStringLiteral("  (discrete)"));
}

static QString intList(const QList<int> &v, bool continuous)
{
    if (v.isEmpty())
        return QStringLiteral("EMPTY");
    QStringList s;
    for (int i = 0; i < v.size(); ++i)
        s << QString::number(v.at(i));
    return s.join(QStringLiteral(", "))
         + (continuous ? QStringLiteral("  (continuous)")
                       : QStringLiteral("  (discrete)"));
}

QString ExposureProbe::run()
{
    QStringList out;

    const QList<QCameraInfo> cams = QCameraInfo::availableCameras();
    out << QString("cameras: %1").arg(cams.size());
    for (int i = 0; i < cams.size(); ++i) {
        out << QString("  [%1] %2  -  %3")
               .arg(i)
               .arg(cams.at(i).deviceName())
               .arg(cams.at(i).description());
    }
    if (cams.isEmpty())
        return out.join(QStringLiteral("\n"));

    // load() is enough to query capabilities. We deliberately do NOT start()
    // -- this must not fight the app's own camera for the device.
    if (!m_camera)
        m_camera = new QCamera(cams.first());
    m_camera->load();

    QCameraExposure *e = m_camera->exposure();
    if (!e) {
        out << QStringLiteral("exposure object: NULL");
        return out.join(QStringLiteral("\n"));
    }

    // The question the whole reflected-metering idea rests on.
    out << QString("isAvailable: %1").arg(e->isAvailable() ? "TRUE" : "FALSE");

    bool cont = false;
    out << "shutterSpeeds: " + realList(e->supportedShutterSpeeds(&cont), cont);
    cont = false;
    out << "isoSensitivities: " + intList(e->supportedIsoSensitivities(&cont), cont);
    cont = false;
    out << "apertures: " + realList(e->supportedApertures(&cont), cont);

    out << QString("ExposureManual supported: %1")
           .arg(e->isExposureModeSupported(QCameraExposure::ExposureManual) ? "TRUE" : "FALSE");
    out << QString("MeteringSpot supported: %1")
           .arg(e->isMeteringModeSupported(QCameraExposure::MeteringSpot) ? "TRUE" : "FALSE");

    // Live values, and the requested ones beside them. The docs say requested*
    // returns -1 when automatic is on. So -1 means "auto, ask the live value",
    // and 0 means the backend never filled the field in at all. That
    // distinction is the whole reason for this probe.
    out << QString("live      shutterSpeed %1   iso %2   aperture %3")
           .arg(e->shutterSpeed()).arg(e->isoSensitivity()).arg(e->aperture());
    out << QString("requested shutterSpeed %1   iso %2   aperture %3")
           .arg(e->requestedShutterSpeed()).arg(e->requestedIsoSensitivity()).arg(e->requestedAperture());

    const QString s = out.join(QStringLiteral("\n"));
    qDebug().noquote() << "\n=== fiat lux exposure probe ===\n" << s << "\n===============================";
    return s;
}
