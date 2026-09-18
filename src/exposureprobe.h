#ifndef EXPOSUREPROBE_H
#define EXPOSUREPROBE_H

#include <QObject>
#include <QString>

class QCamera;

// Asks the camera what it can actually tell us about its own exposure.
//
// QML's CameraExposure exposes the VALUES but not the CAPABILITIES: there is
// no isAvailable(), and no supportedShutterSpeeds(). So from QML the only way
// to find out is to read a value and interpret a zero -- which is guessing,
// and we have done enough of that.
class ExposureProbe : public QObject
{
    Q_OBJECT
public:
    explicit ExposureProbe(QObject *parent = 0);
    ~ExposureProbe();

    Q_INVOKABLE QString run();

private:
    QCamera *m_camera;
};

#endif
