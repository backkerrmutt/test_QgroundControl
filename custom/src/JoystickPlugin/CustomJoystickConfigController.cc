#include "CustomJoystickConfigController.h"
#include "CustomPlugin.h"
#include "QGCCorePlugin.h"

CustomJoystickConfigController::CustomJoystickConfigController(QObject* parent)
    : JoystickConfigController()
{
    setParent(parent);

    auto* p = qobject_cast<CustomPlugin*>(QGCCorePlugin::instance());
    _axisRouter = p ? p->axisActionRouter() : nullptr;   // axisActionRouter() คืน QObject*
}
