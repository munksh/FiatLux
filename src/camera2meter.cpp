// SPDX-License-Identifier: BSD-3-Clause
//
// Adapted from Camera2Preview in RAWfish (https://github.com/Logic-gate/RAWfish),
// BSD-3-Clause; see LICENSE.RAWfish.

#include "camera2meter.h"

#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickWindow>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QStringList>
#include <QTransform>
#include <QtGlobal>

#include <climits>
#include <cmath>

namespace {

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

}

Camera2Meter::Camera2Meter(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
    // A helper that dies at once (camera still held by the page underneath,
    // say) must not be respawned in a tight loop.
    m_retry.setSingleShot(true);
    m_retry.setInterval(1000);
    connect(&m_retry, &QTimer::timeout, this, &Camera2Meter::restart);
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
    restart();
}

bool Camera2Meter::available() const
{
    return QFileInfo(helperPath()).isExecutable();
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

QString Camera2Meter::helperPath() const
{
    const QString override = QString::fromLocal8Bit(qgetenv("FIATLUX_CAMERA2_HELPER"));
    return override.isEmpty()
            ? QStringLiteral("/usr/libexec/rawfish/sfos-camera2-probe")
            : override;
}

void Camera2Meter::restart()
{
    stop();
    if (!m_active)
        return;
    if (!available()) {
        setErrorString(tr("Camera2 helper not found at %1. Is RAWfish installed?").arg(helperPath()));
        return;
    }
    if (!m_probed)
        startProbe();
    else
        startPreview();
}

// Run without arguments, the helper prints the camera's capabilities as JSON.
// All the meter wants from it is the lens aperture, which on a phone is fixed.
void Camera2Meter::startProbe()
{
    m_probeOutput.clear();
    m_probe = new QProcess(this);
    m_probe->setProgram(helperPath());
    connect(m_probe, &QProcess::readyReadStandardOutput, this, [this]() {
        if (m_probe)
            m_probeOutput.append(m_probe->readAllStandardOutput());
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
    m_probed = true;

    const int start = m_probeOutput.indexOf('{');
    const QJsonObject root = start >= 0
            ? QJsonDocument::fromJson(m_probeOutput.mid(start)).object()
            : QJsonObject();
    const QJsonArray cameras = root.value(QStringLiteral("cameras")).toArray();
    qreal aperture = 0.0;
    for (const QJsonValue &value : cameras) {
        const QJsonObject camera = value.toObject();
        if (camera.value(QStringLiteral("id")).toString() != m_cameraId)
            continue;
        const QJsonArray values = camera.value(QStringLiteral("aperture")).toObject()
                .value(QStringLiteral("values")).toArray();
        if (!values.isEmpty())
            aperture = values.first().toDouble();
    }
    if (!qFuzzyCompare(m_aperture + 1.0, aperture + 1.0)) {
        m_aperture = aperture;
        emit apertureChanged();
        emit exposureChanged();
    }
    if (aperture <= 0.0)
        setErrorString(tr("The camera did not report its aperture"));

    if (m_active)
        startPreview();
}

void Camera2Meter::startPreview()
{
    m_buffer.clear();
    m_process = new QProcess(this);
    m_process->setProgram(helperPath());
    QStringList arguments;
    arguments << QStringLiteral("--preview")
              << QStringLiteral("--camera") << m_cameraId
              << QStringLiteral("--size")
              << QStringLiteral("%1x%2").arg(m_previewSize.width()).arg(m_previewSize.height())
              << QStringLiteral("--frames") << QStringLiteral("10000")
              << QStringLiteral("--timeout") << QStringLiteral("3600");
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
        if (m_aperture > 0.0)
            setErrorString(QString());
        sendSettings();
    } else {
        setErrorString(m_process->errorString());
        m_process->deleteLater();
        m_process = nullptr;
    }
}

// Everything automatic: continuous focus, no compensation, no scene mode,
// auto ISO and shutter. The meter reads what auto-exposure chooses, so
// nothing here may bias it.
void Camera2Meter::sendSettings()
{
    if (m_process && m_process->state() == QProcess::Running)
        m_process->write("settings continuous 0.0000 0 manual 0 0 0 0 0 0 1.0000\n");
}

void Camera2Meter::stop()
{
    m_retry.stop();
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
}

void Camera2Meter::previewFinished(int, QProcess::ExitStatus)
{
    if (!m_process)
        return;
    m_process->deleteLater();
    m_process = nullptr;
    if (m_running) {
        m_running = false;
        emit runningChanged();
    }
    if (m_active)
        m_retry.start();
}

void Camera2Meter::readErrors()
{
    if (!m_process)
        return;
    const QStringList lines = QString::fromLocal8Bit(m_process->readAllStandardError())
            .split(QLatin1Char('\n'), QString::SkipEmptyParts);
    QStringList real;
    for (const QString &line : lines) {
        if (!line.startsWith(QStringLiteral("capture-timing ")))
            real.append(line.trimmed());
    }
    if (!real.isEmpty())
        setErrorString(real.join(QLatin1Char('\n')));
}

void Camera2Meter::setErrorString(const QString &errorString)
{
    if (m_errorString == errorString)
        return;
    m_errorString = errorString;
    emit errorStringChanged();
}

// ---- the stream ----
//
// stdout carries two packet kinds, each behind a four-byte magic:
//   SF2P  u32 width, u32 height, u32 bytes, then RGB888 pixels
//   SF2M  u32 bytes, then "focal=4.200 iso=125 shutter=8000000"
// The metadata packet is written only when auto-exposure changes its mind.

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
        if (first)
            emit hasFrameChanged();
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
        }
    }
    if (changed)
        emit exposureChanged();
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
