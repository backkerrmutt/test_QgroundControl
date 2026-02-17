#pragma once

#include "JoystickConfigController.h"
#include <QtCore/QObject>

class CustomJoystickConfigController : public JoystickConfigController
{
    Q_OBJECT
    Q_PROPERTY(QObject* axisActionRouter READ axisActionRouter CONSTANT)

   public:
    Q_INVOKABLE explicit CustomJoystickConfigController(QObject* parent = nullptr);

    QObject* axisActionRouter() const { return _axisRouter; }

   private:
    QObject* _axisRouter = nullptr;
};
