// SPDX-License-Identifier: BSD-3-Clause
//
// Adapted from Camera2Preview in RAWfish (https://github.com/Logic-gate/RAWfish),
// BSD-3-Clause; see LICENSE.RAWfish.

#include "camera2meter.h"

#include <QColor>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QFontMetrics>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QProcessEnvironment>
#include <QQuickWindow>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QStandardPaths>
#include <QThreadPool>
#include <QTransform>
#include <QtGlobal>

#include <climits>
#include <cmath>

namespace {

const char *const OwnHelper = "/usr/libexec/harbour-fiatlux/camera2-helper";
const char *const RawfishHelper = "/usr/libexec/rawfish/sfos-camera2-probe";
const char *const BridgeDir = "/usr/libexec/droid-hybris/system/lib64/";
const char *const OwnBridge = "libfiatluxcamera2.so";
const char *const RawfishBridge = "libsfoscamera2.so";

// What the camera said about itself. Asking takes the better part of a
// second and the answer does not change while the app runs, so every meter
// in the app (the meter page, the calibrate page) shares one answer.
QByteArray s_probeJson;

quint32 readLe32(const char *data)
{
    const uchar *bytes = reinterpret_cast<const uchar *>(data);
    return quint32(bytes[0])
            | (quint32(bytes[1]) << 8)
            | (quint32(bytes[2]) << 16)
            | (quint32(bytes[3]) << 24);
}

int normalisedOrientation(int degrees)
{
    return ((degrees % 360) + 360) % 360;
}

// Helper chatter that is not an error: timing lines, the droidmedia preload
// warning, and anything else the helper writes while it is working normally.
bool isNoise(const QString &line)
{
    return line.startsWith(QStringLiteral("capture-"))
            || line.startsWith(QStringLiteral("Warning:"))
            || line.startsWith(QStringLiteral("preview-"));
}

// Largest 4:3 JPEG size no wider than 2600 px: plenty for a note of what you
// metered, and quick to take. Anything else if the camera offers no 4:3.
QSize chooseJpegSize(const QJsonArray &outputs)
{
    QSize best;
    QSize fallback;
    for (const QJsonValue &value : outputs) {
        const QJsonObject o = value.toObject();
        const QSize size(o.value(QStringLiteral("width")).toInt(),
                         o.value(QStringLiteral("height")).toInt());
        if (size.width() <= 0 || size.height() <= 0)
            continue;
        const bool fourThree = size.width() * 3 == size.height() * 4;
        if (fourThree && size.width() <= 2600
                && size.width() * size.height() > best.width() * best.height())
            best = size;
        if (size.width() <= 2600
                && size.width() * size.height() > fallback.width() * fallback.height())
            fallback = size;
    }
    return best.isValid() ? best : fallback;
}

QString uniquePath(const QString &dir, const QString &stem)
{
    QString path = dir + QLatin1Char('/') + stem + QStringLiteral(".jpg");
    for (int n = 2; QFile::exists(path) && n < 100; ++n)
        path = dir + QLatin1Char('/') + stem + QLatin1Char('-') + QString::number(n) + QStringLiteral(".jpg");
    return path;
}

// The strip, the same one the viewfinder shows: the pair and the film speed
// on the first line, the speed in the viewfinder's amber, and which camera,
// film and frame on the second.
void burnStrip(QImage &image, const QString &aperture, const QString &speed,
               const QString &iso, const QString &detail)
{
    const int side = qMin(image.width(), image.height());
    QFont f1;
    f1.setPixelSize(qMax(8, int(side * 0.052)));
    QFont f2;
    f2.setPixelSize(qMax(6, int(side * 0.033)));
    const QFontMetrics m1(f1);
    const QFontMetrics m2(f2);
    const qreal pad = side * 0.024;
    const qreal gap = side * 0.006;
    const bool twoLines = !detail.isEmpty();
    const qreal barHeight = pad * 2 + m1.height() + (twoLines ? gap + m2.height() : 0.0);

    QPainter p(&image);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.setRenderHint(QPainter::TextAntialiasing, true);
    const QRectF bar(0, image.height() - barHeight, image.width(), barHeight);
    p.fillRect(bar, QColor(0, 0, 0, 166));

    const QColor text(0xF4, 0xEE, 0xD8);
    const QColor amber(0xC8, 0x79, 0x41);

    const QStringList parts = { aperture, speed, iso };
    const int spacing = int(f1.pixelSize() * 1.1);
    int total = spacing * (parts.size() - 1);
    for (const QString &part : parts)
        total += m1.width(part);
    qreal x = (image.width() - total) / 2.0;
    const qreal top1 = bar.top() + pad;
    p.setFont(f1);
    for (int i = 0; i < parts.size(); ++i) {
        const int w = m1.width(parts.at(i));
        p.setPen(i == 1 ? amber : text);
        p.drawText(QRectF(x, top1, w + 2, m1.height()), Qt::AlignLeft | Qt::AlignVCenter, parts.at(i));
        x += w + spacing;
    }

    if (twoLines) {
        const QString line = m2.elidedText(detail, Qt::ElideMiddle, int(image.width() - pad * 2));
        QColor dim = text;
        dim.setAlphaF(0.8);
        p.setFont(f2);
        p.setPen(dim);
        p.drawText(QRectF(pad, top1 + m1.height() + gap, image.width() - pad * 2, m2.height()),
                   Qt::AlignHCenter | Qt::AlignVCenter, line);
    }
    p.end();
}

QImage cropToAspect(const QImage &source, qreal aspect)
{
    if (source.isNull() || !(aspect > 0.0))
        return source;
    const qreal sourceAspect = qreal(source.width()) / source.height();
    QRect r = source.rect();
    if (sourceAspect > aspect) {
        const int w = qRound(source.height() * aspect);
        r = QRect((source.width() - w) / 2, 0, w, source.height());
    } else if (sourceAspect < aspect) {
        const int h = qRound(source.width() / aspect);
        r = QRect(0, (source.height() - h) / 2, source.width(), h);
    }
    return source.copy(r);
}

}

// ---- the shot, off the GUI thread ----

void ShotJob::run()
{
    QImage image;
    bool fullPhoto = false;
    if (!sourcePath.isEmpty()) {
        QImageReader reader(sourcePath);
        reader.setAutoTransform(true);
        image = reader.read();
        fullPhoto = !image.isNull();
    }
    if (image.isNull())
        image = fallback;

    QString error;
    if (image.isNull()) {
        error = QStringLiteral("no picture to save");
    } else {
        image = cropToAspect(image, aspect).convertToFormat(QImage::Format_RGB32);
        // A preview frame is small; scale it up so the strip stays legible.
        if (!fullPhoto && image.width() < 1080)
            image = image.scaledToWidth(1080, Qt::SmoothTransformation);
        burnStrip(image, aperture, speed, iso, detail);
        if (!image.save(outputPath, "JPG", 90))
            error = QStringLiteral("could not write %1").arg(outputPath);
    }
    if (!sourcePath.isEmpty())
        QFile::remove(sourcePath);
    emit finished(error.isEmpty() ? outputPath : QString(), fullPhoto, error);
    deleteLater();
}

// ---- the meter ----

Camera2Meter::Camera2Meter(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
    // A helper that dies at once (camera still held by the page underneath,
    // say) must not be respawned in a tight loop.
    m_retry.setSingleShot(true);
    connect(&m_retry, &QTimer::timeout, this, &Camera2Meter::retry);
    m_captureTimer.setInterval(50);
    connect(&m_captureTimer, &QTimer::timeout, this, &Camera2Meter::pollCapture);
}

Camera2Meter::~Camera2Meter()
{
    stop();
}

void Camera2Meter::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
    m_failures = 0;
    restart();
}

QString Camera2Meter::helperPath() const
{
    const QString override = QString::fromLocal8Bit(qgetenv("FIATLUX_CAMERA2_HELPER"));
    if (!override.isEmpty())
        return override;
    if (QFileInfo(QString::fromLatin1(OwnHelper)).isExecutable())
        return QString::fromLatin1(OwnHelper);
    if (QFileInfo(QString::fromLatin1(RawfishHelper)).isExecutable())
        return QString::fromLatin1(RawfishHelper);
    return QString::fromLatin1(OwnHelper);
}

QString Camera2Meter::bridgeName() const
{
    const QString override = QString::fromLocal8Bit(qgetenv("FIATLUX_CAMERA2_BRIDGE"));
    if (!override.isEmpty())
        return override;
    const QString dir = QString::fromLatin1(BridgeDir);
    if (QFile::exists(dir + QString::fromLatin1(OwnBridge)))
        return QString::fromLatin1(OwnBridge);
    if (QFile::exists(dir + QString::fromLatin1(RawfishBridge)))
        return QString::fromLatin1(RawfishBridge);
    return QString::fromLatin1(OwnBridge);
}

QProcessEnvironment Camera2Meter::helperEnvironment() const
{
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("SFOS_CAMERA2_BRIDGE"), bridgeName());
    return env;
}

bool Camera2Meter::available() const
{
    const QString bridge = bridgeName();
    const bool bridgeThere = bridge.contains(QLatin1Char('/'))
            ? QFile::exists(bridge)
            : QFile::exists(QString::fromLatin1(BridgeDir) + bridge);
    return QFileInfo(helperPath()).isExecutable() && bridgeThere;
}

bool Camera2Meter::starting() const
{
    return m_active && m_frame.isNull() && m_errorString.isEmpty();
}

void Camera2Meter::updateStarting()
{
    const bool now = starting();
    if (now != m_lastStarting) {
        m_lastStarting = now;
        emit startingChanged();
    }
}

void Camera2Meter::setCameraId(const QString &cameraId)
{
    if (m_cameraId == cameraId)
        return;
    m_cameraId = cameraId;
    m_probed = false;
    m_aperture = 0.0;
    emit cameraIdChanged();
    emit apertureChanged();
    restart();
}

void Camera2Meter::setPreviewSize(const QSize &previewSize)
{
    if (m_previewSize == previewSize || !previewSize.isValid())
        return;
    m_previewSize = previewSize;
    emit previewSizeChanged();
    restart();
}

void Camera2Meter::setOrientation(int orientation)
{
    if (m_orientation == orientation)
        return;
    m_orientation = orientation;
    emit orientationChanged();
}

void Camera2Meter::setMirror(bool mirror)
{
    if (m_mirror == mirror)
        return;
    m_mirror = mirror;
    emit mirrorChanged();
}

void Camera2Meter::setFill(bool fill)
{
    if (m_fill == fill)
        return;
    m_fill = fill;
    emit fillChanged();
    update();
}

void Camera2Meter::setPhotos(bool photos)
{
    if (m_photos == photos)
        return;
    m_photos = photos;
    emit photosChanged();
    emit photoSizeChanged();
    restart();
}

QString Camera2Meter::photoSize() const
{
    if (!m_photos || !m_jpegSize.isValid())
        return QString();
    return QStringLiteral("%1 × %2").arg(m_jpegSize.width()).arg(m_jpegSize.height());
}

bool Camera2Meter::metered() const
{
    return m_aperture > 0.0 && m_iso > 0 && m_exposureNs > 0.0;
}

qreal Camera2Meter::ev100() const
{
    if (!metered())
        return qQNaN();
    const qreal t = m_exposureNs / 1e9;
    return std::log2((m_aperture * m_aperture) / t) - std::log2(m_iso / 100.0);
}

// ---- metering point ----

QRectF Camera2Meter::drawRect() const
{
    const QRectF target(0, 0, width(), height());
    if (m_frame.isNull() || target.isEmpty())
        return target;
    const QSizeF imageSize = m_frame.size();
    const qreal scale = m_fill
            ? qMax(target.width() / imageSize.width(), target.height() / imageSize.height())
            : qMin(target.width() / imageSize.width(), target.height() / imageSize.height());
    const QSizeF drawSize(imageSize.width() * scale, imageSize.height() * scale);
    return QRectF(target.center().x() - drawSize.width() / 2,
                  target.center().y() - drawSize.height() / 2,
                  drawSize.width(), drawSize.height());
}

void Camera2Meter::meterAt(qreal x, qreal y)
{
    // Tapped point -> fraction of the displayed image -> fraction of the
    // sensor frame, undoing the crop, the mirror and the rotation in the
    // reverse of the order parseFrames() applied them.
    const QRectF rect = drawRect();
    if (rect.isEmpty())
        return;
    qreal a = (x * width() - rect.x()) / rect.width();
    qreal b = (y * height() - rect.y()) / rect.height();
    a = qBound<qreal>(0.0, a, 1.0);
    b = qBound<qreal>(0.0, b, 1.0);
    if (m_mirror)
        a = 1.0 - a;

    qreal sx = a;
    qreal sy = b;
    switch (normalisedOrientation(m_orientation)) {
    case 90:  sx = b;       sy = 1.0 - a; break;
    case 180: sx = 1.0 - a; sy = 1.0 - b; break;
    case 270: sx = 1.0 - b; sy = a;       break;
    default: break;
    }

    m_focusX = sx;
    m_focusY = sy;
    emit spotChanged();
    if (m_process && m_process->state() == QProcess::Running) {
        m_process->write(QStringLiteral("focus %1 %2\n")
                         .arg(m_focusX, 0, 'f', 4)
                         .arg(m_focusY, 0, 'f', 4)
                         .toLocal8Bit());
    }
}

void Camera2Meter::meterWholeFrame()
{
    m_focusX = -1.0;
    m_focusY = -1.0;
    emit spotChanged();
    if (m_process && m_process->state() == QProcess::Running)
        m_process->write("focus-reset\n");
}

// ---- process lifecycle ----

void Camera2Meter::restart()
{
    stop();
    setErrorString(QString());
    if (!m_active) {
        updateStarting();
        return;
    }
    if (!available()) {
        setErrorString(tr("The camera helper is missing. Reinstalling Fiat Lux should bring it back."));
        return;
    }
    if (!m_probed && !s_probeJson.isEmpty())
        applyProbe(s_probeJson);
    if (!m_probed)
        startProbe();
    else
        startPreview();
    updateStarting();
}

// After the helper stopped by itself. A helper that ran and simply reached
// its frame limit is restarted at once and the picture is kept, so the
// viewfinder does not blink; one that failed backs off.
void Camera2Meter::retry()
{
    if (!m_active)
        return;
    if (!m_probed) {
        startProbe();
        return;
    }
    startPreview();
}

// Run without arguments, the helper prints the camera's capabilities as JSON:
// the lens aperture, which on a phone is fixed, and the sizes it can take a
// JPEG at.
void Camera2Meter::startProbe()
{
    m_probeOutput.clear();
    m_stderrTail.clear();
    m_probe = new QProcess(this);
    m_probe->setProgram(helperPath());
    m_probe->setProcessEnvironment(helperEnvironment());
    connect(m_probe, &QProcess::readyReadStandardOutput, this, [this]() {
        if (m_probe)
            m_probeOutput.append(m_probe->readAllStandardOutput());
    });
    connect(m_probe, &QProcess::readyReadStandardError, this, [this]() {
        if (!m_probe)
            return;
        const QStringList lines = QString::fromLocal8Bit(m_probe->readAllStandardError())
                .split(QLatin1Char('\n'), QString::SkipEmptyParts);
        for (const QString &line : lines) {
            if (!isNoise(line.trimmed()))
                m_stderrTail.append(line.trimmed());
        }
        while (m_stderrTail.size() > 3)
            m_stderrTail.removeFirst();
    });
    connect(m_probe,
            static_cast<void (QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
            this, &Camera2Meter::probeFinished);
    m_probe->start();
}

void Camera2Meter::probeFinished(int, QProcess::ExitStatus)
{
    if (!m_probe)
        return;
    m_probeOutput.append(m_probe->readAllStandardOutput());
    m_probe->deleteLater();
    m_probe = nullptr;

    const int start = m_probeOutput.indexOf('{');
    const QByteArray json = start >= 0 ? m_probeOutput.mid(start) : QByteArray();
    const QJsonArray cameras = QJsonDocument::fromJson(json).object()
            .value(QStringLiteral("cameras")).toArray();
    if (cameras.isEmpty()) {
        ++m_failures;
        if (m_failures >= 2) {
            const QString detail = m_stderrTail.join(QLatin1Char('\n'));
            setErrorString(detail.isEmpty()
                           ? tr("The camera did not answer.")
                           : tr("The camera did not answer.") + QLatin1Char('\n') + detail);
        }
        if (m_active)
            m_retry.start(qMin(8000, 1000 << qMin(3, m_failures - 1)));
        updateStarting();
        return;
    }

    s_probeJson = json;
    applyProbe(json);
    if (m_active)
        startPreview();
}

void Camera2Meter::applyProbe(const QByteArray &json)
{
    const QJsonArray cameras = QJsonDocument::fromJson(json).object()
            .value(QStringLiteral("cameras")).toArray();
    qreal aperture = 0.0;
    QSize jpegSize;
    for (const QJsonValue &value : cameras) {
        const QJsonObject camera = value.toObject();
        if (camera.value(QStringLiteral("id")).toString() != m_cameraId)
            continue;
        const QJsonArray values = camera.value(QStringLiteral("aperture")).toObject()
                .value(QStringLiteral("values")).toArray();
        if (!values.isEmpty())
            aperture = values.first().toDouble();
        jpegSize = chooseJpegSize(camera.value(QStringLiteral("jpeg_outputs")).toArray());
    }
    m_probed = true;
    if (jpegSize != m_jpegSize) {
        m_jpegSize = jpegSize;
        emit photoSizeChanged();
    }
    if (!qFuzzyCompare(m_aperture + 1.0, aperture + 1.0)) {
        m_aperture = aperture;
        emit apertureChanged();
        emit exposureChanged();
    }
    if (aperture <= 0.0)
        setErrorString(tr("The camera did not report its aperture, so it cannot meter."));
}

void Camera2Meter::startPreview()
{
    m_buffer.clear();
    m_stderrTail.clear();
    m_frameThisRun = false;
    m_process = new QProcess(this);
    m_process->setProgram(helperPath());
    m_process->setProcessEnvironment(helperEnvironment());
    QStringList arguments;
    arguments << QStringLiteral("--preview")
              << QStringLiteral("--camera") << m_cameraId
              << QStringLiteral("--size")
              << QStringLiteral("%1x%2").arg(m_previewSize.width()).arg(m_previewSize.height())
              // The helper's ceiling. At its frame rate that is a few
              // minutes; when it runs out it is restarted without a blink.
              << QStringLiteral("--frames") << QStringLiteral("10000")
              << QStringLiteral("--timeout") << QStringLiteral("3600");
    if (m_photos && m_jpegSize.isValid()) {
        arguments << QStringLiteral("--jpeg-size")
                  << QStringLiteral("%1x%2").arg(m_jpegSize.width()).arg(m_jpegSize.height())
                  << QStringLiteral("--quality") << QStringLiteral("92")
                  << QStringLiteral("--orientation")
                  << QString::number(normalisedOrientation(m_orientation));
    }
    if (spot()) {
        arguments << QStringLiteral("--focus-x") << QString::number(m_focusX, 'f', 4)
                  << QStringLiteral("--focus-y") << QString::number(m_focusY, 'f', 4);
    }
    m_process->setArguments(arguments);
    connect(m_process, &QProcess::readyReadStandardOutput, this, &Camera2Meter::readFrames);
    connect(m_process, &QProcess::readyReadStandardError, this, &Camera2Meter::readErrors);
    connect(m_process,
            static_cast<void (QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
            this, &Camera2Meter::previewFinished);
    m_process->start();
    if (m_process->waitForStarted(1000)) {
        m_running = true;
        emit runningChanged();
        sendSettings();
    } else {
        setErrorString(tr("The camera helper would not start: %1").arg(m_process->errorString()));
        m_process->deleteLater();
        m_process = nullptr;
    }
    updateStarting();
}

// Everything automatic: continuous focus, no compensation, no scene mode,
// auto ISO and shutter. The meter reads what auto-exposure chooses, so
// nothing here may bias it.
void Camera2Meter::sendSettings()
{
    if (m_process && m_process->state() == QProcess::Running)
        m_process->write("settings continuous 0.0000 0 manual 0 0 0 0 0 0 1.0000\n");
}

void Camera2Meter::stop(bool keepPicture)
{
    m_retry.stop();
    if (m_shot.pending && m_shot.waitingForJpeg)
        finishCapture(false);
    if (m_probe) {
        QProcess *probe = m_probe;
        m_probe = nullptr;
        probe->disconnect(this);
        probe->kill();
        probe->waitForFinished(500);
        probe->deleteLater();
    }
    if (m_process) {
        QProcess *process = m_process;
        m_process = nullptr;
        process->disconnect(this);
        if (process->state() != QProcess::NotRunning) {
            process->terminate();
            if (!process->waitForFinished(500)) {
                process->kill();
                process->waitForFinished(500);
            }
        }
        process->deleteLater();
    }
    m_buffer.clear();
    if (m_running) {
        m_running = false;
        emit runningChanged();
    }
    if (keepPicture)
        return;
    if (!m_frame.isNull()) {
        m_frame = QImage();
        emit hasFrameChanged();
        update();
    }
    if (m_iso != 0 || m_exposureNs != 0.0) {
        m_iso = 0;
        m_exposureNs = 0.0;
        emit exposureChanged();
    }
    updateStarting();
}

void Camera2Meter::previewFinished(int exitCode, QProcess::ExitStatus)
{
    if (!m_process)
        return;
    m_process->readAllStandardError();
    m_process->deleteLater();
    m_process = nullptr;
    if (m_running) {
        m_running = false;
        emit runningChanged();
    }
    if (m_shot.pending && m_shot.waitingForJpeg)
        finishCapture(false);
    if (!m_active)
        return;

    if (m_frameThisRun) {
        // Ran, then stopped: the frame limit, most likely. Carry on.
        m_failures = 0;
        m_retry.start(100);
        return;
    }

    // Failed before a single frame. The first time is often only the camera
    // still being released by another page, so say nothing yet.
    ++m_failures;
    if (m_failures >= 2) {
        const QString detail = m_stderrTail.join(QLatin1Char('\n'));
        setErrorString(detail.isEmpty()
                       ? tr("The camera stopped (code %1).").arg(exitCode)
                       : detail);
    }
    m_retry.start(qMin(8000, 1000 << qMin(3, m_failures - 1)));
    updateStarting();
}

void Camera2Meter::readErrors()
{
    if (!m_process)
        return;
    const QStringList lines = QString::fromLocal8Bit(m_process->readAllStandardError())
            .split(QLatin1Char('\n'), QString::SkipEmptyParts);
    for (const QString &line : lines) {
        const QString t = line.trimmed();
        if (!t.isEmpty() && !isNoise(t))
            m_stderrTail.append(t);
    }
    while (m_stderrTail.size() > 3)
        m_stderrTail.removeFirst();
}

void Camera2Meter::setErrorString(const QString &errorString)
{
    if (m_errorString == errorString)
        return;
    m_errorString = errorString;
    emit errorStringChanged();
    updateStarting();
}

// ---- the stream ----
//
// stdout carries two packet kinds, each behind a four-byte magic:
//   SF2P  u32 width, u32 height, u32 bytes, then RGB888 pixels
//   SF2M  u32 bytes, then "focal=4.200 iso=125 shutter=8000000", or
//         "capture-status=ok path=... " when a JPEG has been written
// The exposure packet is written only when auto-exposure changes its mind.

void Camera2Meter::readFrames()
{
    if (!m_process)
        return;
    m_buffer.append(m_process->readAllStandardOutput());
    parseFrames();
}

void Camera2Meter::parseFrames()
{
    static const QByteArray frameMagic("SF2P", 4);
    static const QByteArray metadataMagic("SF2M", 4);
    bool updated = false;

    while (true) {
        if (!m_buffer.startsWith(frameMagic) && !m_buffer.startsWith(metadataMagic)) {
            const int frameMarker = m_buffer.indexOf(frameMagic);
            const int metadataMarker = m_buffer.indexOf(metadataMagic);
            int marker = -1;
            if (frameMarker >= 0 && metadataMarker >= 0)
                marker = qMin(frameMarker, metadataMarker);
            else
                marker = qMax(frameMarker, metadataMarker);
            if (marker < 0) {
                m_buffer.clear();
                break;
            }
            m_buffer.remove(0, marker);
        }

        if (m_buffer.startsWith(metadataMagic)) {
            const int headerBytes = 8;
            if (m_buffer.size() < headerBytes)
                break;
            const quint32 payloadBytes = readLe32(m_buffer.constData() + 4);
            if (payloadBytes == 0 || payloadBytes > 8192) {
                m_buffer.remove(0, metadataMagic.size());
                continue;
            }
            if (m_buffer.size() < headerBytes + int(payloadBytes))
                break;
            parseMetadata(m_buffer.mid(headerBytes, int(payloadBytes)));
            m_buffer.remove(0, headerBytes + int(payloadBytes));
            continue;
        }

        const int headerBytes = 16;
        if (m_buffer.size() < headerBytes)
            break;
        const quint32 w = readLe32(m_buffer.constData() + 4);
        const quint32 h = readLe32(m_buffer.constData() + 8);
        const quint32 frameBytes = readLe32(m_buffer.constData() + 12);
        const quint64 expected = quint64(w) * quint64(h) * 3;
        if (w == 0 || h == 0 || frameBytes == 0 || expected > quint64(INT_MAX)
                || frameBytes != expected) {
            m_buffer.remove(0, frameMagic.size());
            continue;
        }
        if (m_buffer.size() < headerBytes + int(frameBytes))
            break;

        const uchar *bits = reinterpret_cast<const uchar *>(m_buffer.constData() + headerBytes);
        QImage frame = QImage(bits, int(w), int(h), int(w) * 3, QImage::Format_RGB888).copy();
        if (normalisedOrientation(m_orientation) != 0)
            frame = frame.transformed(QTransform().rotate(normalisedOrientation(m_orientation)));
        if (m_mirror)
            frame = frame.mirrored(true, false);
        const bool first = m_frame.isNull();
        m_frame = frame;
        m_frameThisRun = true;
        if (m_failures != 0)
            m_failures = 0;
        if (!m_errorString.isEmpty() && m_aperture > 0.0)
            setErrorString(QString());
        if (first) {
            emit hasFrameChanged();
            updateStarting();
        }
        m_buffer.remove(0, headerBytes + int(frameBytes));
        updated = true;
    }
    if (updated)
        update();
}

void Camera2Meter::parseMetadata(const QByteArray &payload)
{
    const QStringList fields = QString::fromLatin1(payload).simplified().split(QLatin1Char(' '));
    bool changed = false;
    QString captureStatus;
    QString capturePath;
    for (const QString &field : fields) {
        const int separator = field.indexOf(QLatin1Char('='));
        if (separator <= 0)
            continue;
        const QString key = field.left(separator);
        const QString value = field.mid(separator + 1);
        bool ok = false;
        if (key == QLatin1String("iso")) {
            const int iso = value.toInt(&ok);
            if (ok && iso != m_iso) { m_iso = iso; changed = true; }
        } else if (key == QLatin1String("shutter")) {
            const qlonglong ns = value.toLongLong(&ok);
            if (ok && qreal(ns) != m_exposureNs) { m_exposureNs = ns > 0 ? qreal(ns) : 0.0; changed = true; }
        } else if (key == QLatin1String("focal")) {
            const qreal focal = value.toDouble(&ok);
            if (ok && !qFuzzyCompare(m_focalLength + 1.0, focal + 1.0)) { m_focalLength = focal; changed = true; }
        } else if (key == QLatin1String("capture-status")) {
            captureStatus = value;
        } else if (key == QLatin1String("path")) {
            capturePath = value;
        }
    }
    if (changed)
        emit exposureChanged();

    if (!captureStatus.isEmpty() && m_shot.pending && m_shot.waitingForJpeg
            && (capturePath.isEmpty() || capturePath == m_shot.tempPath)) {
        if (captureStatus == QLatin1String("ok"))
            finishCapture(QFileInfo(m_shot.tempPath).size() > 0);
        else
            finishCapture(false);
    }
}

// ---- logging a shot ----

bool Camera2Meter::captureShot(const QString &aperture, const QString &speed,
                               const QString &iso, const QString &detail)
{
    if (m_shot.pending)
        return false;

    QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    if (pictures.isEmpty())
        pictures = QDir::homePath() + QStringLiteral("/Pictures");
    const QString dir = pictures + QStringLiteral("/FiatLux");
    if (!QDir().mkpath(dir)) {
        emit shotFailed(tr("could not create %1").arg(dir));
        return false;
    }

    m_shot = PendingShot();
    m_shot.outputPath = uniquePath(dir, QStringLiteral("fiatlux-")
                                   + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss")));
    m_shot.aperture = aperture;
    m_shot.speed = speed;
    m_shot.iso = iso;
    m_shot.detail = detail;
    m_shot.fallback = m_frame;
    m_shot.aspect = (width() > 0 && height() > 0) ? width() / height() : 1.0;
    m_shot.pending = true;
    emit capturingChanged();

    const bool canJpeg = m_photos && m_jpegSize.isValid() && m_process
            && m_process->state() == QProcess::Running && m_frameThisRun;
    if (!canJpeg) {
        finishCapture(false);
        return true;
    }

    // The helper writes the camera's JPEG here; the finished picture goes to
    // Pictures. No spaces in this path: the helper reads it with scanf.
    QString cache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (cache.isEmpty() || cache.contains(QLatin1Char(' ')))
        cache = QDir::tempPath();
    QDir().mkpath(cache);
    m_shot.tempPath = cache + QStringLiteral("/capture.jpg");
    QFile::remove(m_shot.tempPath);
    m_shot.waitingForJpeg = true;
    m_shot.clock.start();
    sendSettings();
    m_process->write(QStringLiteral("capture-jpeg %1\n").arg(m_shot.tempPath).toLocal8Bit());
    m_captureTimer.start();
    return true;
}

// Belt and braces, as in RAWfish: the helper announces the finished JPEG, but
// if that packet is lost, a file whose size has stopped changing is done.
void Camera2Meter::pollCapture()
{
    if (!m_shot.pending || !m_shot.waitingForJpeg) {
        m_captureTimer.stop();
        return;
    }
    const QFileInfo info(m_shot.tempPath);
    if (info.exists() && info.size() > 0) {
        if (info.size() == m_shot.lastSize) {
            if (++m_shot.stableTicks >= 3) {
                finishCapture(true);
                return;
            }
        } else {
            m_shot.lastSize = info.size();
            m_shot.stableTicks = 0;
        }
    }
    if (m_shot.clock.elapsed() > 6000)
        finishCapture(false);
}

void Camera2Meter::finishCapture(bool jpegReady)
{
    m_captureTimer.stop();
    if (!m_shot.pending)
        return;
    m_shot.waitingForJpeg = false;

    ShotJob *job = new ShotJob;
    job->setAutoDelete(false);
    job->sourcePath = jpegReady ? m_shot.tempPath : QString();
    job->fallback = m_shot.fallback;
    job->outputPath = m_shot.outputPath;
    job->aspect = m_shot.aspect;
    job->aperture = m_shot.aperture;
    job->speed = m_shot.speed;
    job->iso = m_shot.iso;
    job->detail = m_shot.detail;
    m_shot.fallback = QImage();
    connect(job, &ShotJob::finished, this, &Camera2Meter::shotProcessed, Qt::QueuedConnection);

    if (QFontDatabase::supportsThreadedFontRendering())
        QThreadPool::globalInstance()->start(job);
    else
        job->run();
}

void Camera2Meter::shotProcessed(const QString &path, bool fullPhoto, const QString &error)
{
    m_shot = PendingShot();
    emit capturingChanged();
    if (error.isEmpty())
        emit shotSaved(path, fullPhoto);
    else
        emit shotFailed(error);
}

QSGNode *Camera2Meter::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    delete oldNode;
    if (m_frame.isNull() || width() <= 0 || height() <= 0 || !window())
        return nullptr;

    QSGTexture *texture = window()->createTextureFromImage(m_frame);
    if (!texture)
        return nullptr;
    texture->setFiltering(QSGTexture::Linear);

    QSGSimpleTextureNode *node = new QSGSimpleTextureNode;
    node->setOwnsTexture(true);
    node->setTexture(texture);
    node->setRect(drawRect());
    return node;
}
