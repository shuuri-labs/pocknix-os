#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

class Host : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool gamescope READ gamescope CONSTANT)

public:
    using QObject::QObject;
    bool gamescope() const { return qEnvironmentVariableIsSet("GAMESCOPE_WAYLAND_DISPLAY"); }
};
