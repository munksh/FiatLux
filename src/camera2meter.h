// SPDX-License-Identifier: BSD-3-Clause
//
// Adapted from Camera2Preview in RAWfish (https://github.com/Logic-gate/RAWfish),
// BSD-3-Clause; see LICENSE.RAWfish. Trimmed to what a light meter needs: the
// live viewfinder, the exposure the camera's auto-exposure chose, and a
// metering point.

#ifndef CAMERA2METER_H
#define CAMERA2METER_H

#include <QByteArray>
#include <QImage>
#include <QProcess>
#include <QQuickItem>
#include <QRectF>
#include <QSize>
#include <QString>
#include <QTimer>

class Camera2Meter : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged)
    Q_PROPERTY(QString cameraId READ cameraId WRITE setCameraId NOTIFY cameraIdChanged)
    Q_PROPERTY(QSize previewSize READ previewSize WRITE setPreviewSize NOTIFY previewSizeChanged)
    Q_PROPERTY(int orientation READ orientation WRITE setOrientation NOTIFY orientationChanged)
    Q_PROPERTY(bool mirror READ mirror WRITE setMirror NOTIFY mirrorChanged)
    Q_PROPERTY(bool fill READ fill WRITE setFill NOTIFY fillChanged)
    Q_PROPERTY(qreal aperture READ aperture NOTIFY apertureChanged)
    Q_PROPERTY(qreal focalLength READ focalLength NOTIFY exposureChanged)
    Q_PROPERTY(int iso READ iso NOTIFY exposureChanged)
    Q_PROPERTY(qreal exposureTime READ exposureTime NOTIFY exposureChanged)
    Q_PROPERTY(qreal ev100 READ ev100 NOTIFY exposureChanged)
    Q_PROPERTY(bool metered READ metered NOTIFY exposureChanged)
    Q_PROPERTY(bool spot READ spot NOTIFY spotChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)

public:
    explicit Camera2Meter(QQuickItem *parent = nullptr);
    ~Camera2Meter() override;

    bool active() const { return m_active; }
    void setActive(bool active);

    bool available() const;
    bool running() const { return m_running; }
    bool hasFrame() const { return !m_frame.isNull(); }

    QString cameraId() const { return m_cameraId; }
    void setCameraId(const QString &cameraId);

    QSize previewSize() const { return m_previewSize; }
    void setPreviewSize(const QSize &previewSize);

    int orientation() const { return m_orientation; }
    void setOrientation(int orientation);

    bool mirror() const { return m_mirror; }
    void setMirror(bool mirror);

    bool fill() const { return m_fill; }
    void setFill(bool fill);

    qreal aperture() const { return m_aperture; }
    qreal focalLength() const { return m_focalLength; }
    int iso() const { return m_iso; }
    qreal exposureTime() const { return m_exposureNs / 1e9; }
    qreal ev100() const;
    bool metered() const;
    bool spot() const { return m_focusX >= 0.0 && m_focusY >= 0.0; }

    QString errorString() const { return m_errorString; }

    // x and y are fractions of this item's width and height, as tapped.
    Q_INVOKABLE void meterAt(qreal x, qreal y);
    Q_INVOKABLE void meterWholeFrame();
    Q_INVOKABLE void restart();

signals:
    void activeChanged();
    void runningChanged();
    void hasFrameChanged();
    void cameraIdChanged();
    void previewSizeChanged();
    void orientationChanged();
    void mirrorChanged();
    void fillChanged();
    void apertureChanged();
    void exposureChanged();
    void spotChanged();
    void errorStringChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *data) override;

private slots:
    void readFrames();
    void readErrors();
    void previewFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void probeFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    void startProbe();
    void startPreview();
    void stop();
    void sendSettings();
    void parseFrames();
    void parseMetadata(const QByteArray &payload);
    void setErrorString(const QString &errorString);
    QRectF drawRect() const;
    QString helperPath() const;

    bool m_active = false;
    bool m_running = false;
    bool m_probed = false;
    QString m_cameraId = QStringLiteral("0");
    QSize m_previewSize = QSize(640, 480);
    int m_orientation = 90;
    bool m_mirror = false;
    bool m_fill = true;
    qreal m_focusX = -1.0;
    qreal m_focusY = -1.0;

    qreal m_aperture = 0.0;
    qreal m_focalLength = 0.0;
    int m_iso = 0;
    qreal m_exposureNs = 0.0;

    QString m_errorString;
    QImage m_frame;
    QByteArray m_buffer;
    QByteArray m_probeOutput;
    QProcess *m_process = nullptr;
    QProcess *m_probe = nullptr;
    QTimer m_retry;
};

#endif
