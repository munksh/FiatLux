// SPDX-License-Identifier: BSD-3-Clause
//
// Adapted from Camera2Preview in RAWfish (https://github.com/Logic-gate/RAWfish),
// BSD-3-Clause; see LICENSE.RAWfish. Trimmed to what a light meter needs: the
// live viewfinder, the exposure the camera's auto-exposure chose, a metering
// point, and one full photo per logged shot.
//
// Lux carries its own copy of the helper and the Android bridge, so RAWfish
// does not have to be installed:
//
//   /usr/libexec/harbour-fiatlux/camera2-helper                  (Sailfish side)
//   /usr/libexec/droid-hybris/system/lib64/libfiatluxcamera2.so  (Android side)
//
// If either is missing it falls back to RAWfish's, when RAWfish is there.

#ifndef CAMERA2METER_H
#define CAMERA2METER_H

#include <QByteArray>
#include <QElapsedTimer>
#include <QImage>
#include <QProcess>
#include <QQuickItem>
#include <QRectF>
#include <QRunnable>
#include <QSize>
#include <QString>
#include <QStringList>
#include <QTimer>

// Crops a photo (or, failing that, a preview frame) to the viewfinder's
// shape, burns the strip into it and writes the JPEG. Runs on a pool thread so
// the viewfinder does not stall while a 3-megapixel image is decoded.
class ShotJob : public QObject, public QRunnable
{
    Q_OBJECT
public:
    QString sourcePath;      // the camera's JPEG, or empty
    QImage fallback;         // the preview frame, used when there is no JPEG
    QString outputPath;
    qreal aspect = 1.0;      // width / height of the viewfinder
    QString aperture;
    QString speed;
    QString iso;
    QString detail;

    void run() override;

signals:
    void finished(const QString &path, bool fullPhoto, const QString &error);
};

class Camera2Meter : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged)
    Q_PROPERTY(bool starting READ starting NOTIFY startingChanged)
    Q_PROPERTY(bool capturing READ capturing NOTIFY capturingChanged)
    Q_PROPERTY(QString cameraId READ cameraId WRITE setCameraId NOTIFY cameraIdChanged)
    Q_PROPERTY(QSize previewSize READ previewSize WRITE setPreviewSize NOTIFY previewSizeChanged)
    Q_PROPERTY(int orientation READ orientation WRITE setOrientation NOTIFY orientationChanged)
    Q_PROPERTY(bool mirror READ mirror WRITE setMirror NOTIFY mirrorChanged)
    Q_PROPERTY(bool fill READ fill WRITE setFill NOTIFY fillChanged)
    Q_PROPERTY(bool photos READ photos WRITE setPhotos NOTIFY photosChanged)
    Q_PROPERTY(qreal aperture READ aperture NOTIFY apertureChanged)
    Q_PROPERTY(qreal focalLength READ focalLength NOTIFY exposureChanged)
    Q_PROPERTY(int iso READ iso NOTIFY exposureChanged)
    Q_PROPERTY(qreal exposureTime READ exposureTime NOTIFY exposureChanged)
    Q_PROPERTY(qreal ev100 READ ev100 NOTIFY exposureChanged)
    Q_PROPERTY(bool metered READ metered NOTIFY exposureChanged)
    Q_PROPERTY(bool spot READ spot NOTIFY spotChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
    Q_PROPERTY(QString photoSize READ photoSize NOTIFY photoSizeChanged)

public:
    explicit Camera2Meter(QQuickItem *parent = nullptr);
    ~Camera2Meter() override;

    bool active() const { return m_active; }
    void setActive(bool active);

    bool available() const;
    bool running() const { return m_running; }
    bool hasFrame() const { return !m_frame.isNull(); }
    bool starting() const;
    bool capturing() const { return m_shot.pending; }

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

    // Ask the camera for a full-size JPEG stream as well as the preview, so a
    // logged shot is a real photo. Off on the calibrate page, which only
    // meters.
    bool photos() const { return m_photos; }
    void setPhotos(bool photos);

    qreal aperture() const { return m_aperture; }
    qreal focalLength() const { return m_focalLength; }
    int iso() const { return m_iso; }
    qreal exposureTime() const { return m_exposureNs / 1e9; }
    qreal ev100() const;
    bool metered() const;
    bool spot() const { return m_focusX >= 0.0 && m_focusY >= 0.0; }

    QString errorString() const { return m_errorString; }
    QString photoSize() const;

    // x and y are fractions of this item's width and height, as tapped.
    Q_INVOKABLE void meterAt(qreal x, qreal y);
    Q_INVOKABLE void meterWholeFrame();
    Q_INVOKABLE void restart();

    // Take a photo, crop it to the square the viewfinder shows, burn the
    // strip into it and save it under Pictures/FiatLux. Falls back to the
    // preview frame when the camera cannot deliver a JPEG. Answers with
    // shotSaved or shotFailed.
    Q_INVOKABLE bool captureShot(const QString &aperture, const QString &speed,
                                 const QString &iso, const QString &detail);

signals:
    void activeChanged();
    void runningChanged();
    void hasFrameChanged();
    void startingChanged();
    void capturingChanged();
    void cameraIdChanged();
    void previewSizeChanged();
    void orientationChanged();
    void mirrorChanged();
    void fillChanged();
    void photosChanged();
    void apertureChanged();
    void exposureChanged();
    void spotChanged();
    void errorStringChanged();
    void photoSizeChanged();
    void shotSaved(const QString &path, bool fullPhoto);
    void shotFailed(const QString &reason);

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *data) override;

private slots:
    void readFrames();
    void readErrors();
    void previewFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void probeFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void pollCapture();
    void shotProcessed(const QString &path, bool fullPhoto, const QString &error);
    void retry();

private:
    struct PendingShot {
        bool pending = false;
        bool waitingForJpeg = false;
        QString tempPath;
        QString outputPath;
        QString aperture;
        QString speed;
        QString iso;
        QString detail;
        QImage fallback;
        qreal aspect = 1.0;
        qint64 lastSize = -1;
        int stableTicks = 0;
        QElapsedTimer clock;
    };

    void startProbe();
    void applyProbe(const QByteArray &json);
    void startPreview();
    void stop(bool keepPicture = false);
    void sendSettings();
    void parseFrames();
    void parseMetadata(const QByteArray &payload);
    void setErrorString(const QString &errorString);
    void updateStarting();
    void finishCapture(bool jpegReady);
    QRectF drawRect() const;
    QString helperPath() const;
    QString bridgeName() const;
    QProcessEnvironment helperEnvironment() const;

    bool m_active = false;
    bool m_running = false;
    bool m_probed = false;
    bool m_photos = true;
    bool m_lastStarting = false;
    QString m_cameraId = QStringLiteral("0");
    QSize m_previewSize = QSize(640, 480);
    QSize m_jpegSize;
    int m_orientation = 90;
    bool m_mirror = false;
    bool m_fill = true;
    qreal m_focusX = -1.0;
    qreal m_focusY = -1.0;
    int m_failures = 0;
    bool m_frameThisRun = false;

    qreal m_aperture = 0.0;
    qreal m_focalLength = 0.0;
    int m_iso = 0;
    qreal m_exposureNs = 0.0;

    QString m_errorString;
    QStringList m_stderrTail;
    QImage m_frame;
    QByteArray m_buffer;
    QByteArray m_probeOutput;
    QProcess *m_process = nullptr;
    QProcess *m_probe = nullptr;
    QTimer m_retry;
    QTimer m_captureTimer;
    PendingShot m_shot;
};

#endif
