#include "AxisActionRouter.h"
#include "AxisActionRouterCommon.h"

#include "Joystick.h"
#include "Vehicle.h"

#include <QtCore/QMetaObject>
#include <QtCore/QMetaProperty>
#include <QtCore/QCoreApplication>

#include <QtQml/QQmlListReference>
#include <QtGui/QAction>
#include <QDebug>

static QAction* _extractAnyQAction(QObject* obj)
{
    qDebug() << "[AxisRouter] _extractAnyQAction called";

    if (!obj) {
        qDebug() << "[AxisRouter] object is null";
        return nullptr;
    }

    if (auto* qa = qobject_cast<QAction*>(obj)) {
        qDebug() << "[AxisRouter] object is QAction directly";
        return qa;
    }

    static const char* kProps[] = { "action", "qAction", "qtAction" };
    for (const char* p : kProps) {
        const QVariant v = obj->property(p);
        if (!v.isValid()) continue;

        if (auto* qa2 = v.value<QAction*>()) {
            qDebug() << "[AxisRouter] QAction found in property" << p;
            return qa2;
        }

        if (QObject* o = v.value<QObject*>()) {
            if (auto* qa3 = qobject_cast<QAction*>(o)) {
                qDebug() << "[AxisRouter] QAction found via QObject property" << p;
                return qa3;
            }
        }
    }

    const QMetaObject* mo = obj->metaObject();
    for (int i = 0; i < mo->propertyCount(); ++i) {
        const QMetaProperty p = mo->property(i);
        if (!p.isReadable()) continue;

        const QVariant v = obj->property(p.name());

        if (auto* qa4 = v.value<QAction*>()) {
            qDebug() << "[AxisRouter] QAction found in meta property" << p.name();
            return qa4;
        }

        if (QObject* o = v.value<QObject*>()) {
            if (auto* qa5 = qobject_cast<QAction*>(o)) {
                qDebug() << "[AxisRouter] QAction found via QObject meta property" << p.name();
                return qa5;
            }
        }
    }

    qDebug() << "[AxisRouter] QAction not found";
    return nullptr;
}

QAction* AxisActionRouter::_findAppQActionByTitle(const QString& actionTitle) const
{
    qDebug() << "[AxisRouter] find QAction by title:" << actionTitle;

    const QString key = _normalizeTitleKey(actionTitle);
    if (key.isEmpty()) return nullptr;

    const QPointer<QAction> cached = _appActionCache.value(key);
    if (cached) {
        qDebug() << "[AxisRouter] QAction found in cache";
        return cached.data();
    }

    const QList<QAction*> all = qApp ? qApp->findChildren<QAction*>() : QList<QAction*>();
    for (QAction* a : all) {
        if (!a) continue;

        const QString txt = _cleanActionText(a->text());
        if (!txt.isEmpty() && _normalizeTitleKey(txt) == key) {
            qDebug() << "[AxisRouter] QAction matched by text:" << txt;
            _appActionCache.insert(key, a);
            return a;
        }

        const QString on = a->objectName().trimmed();
        if (!on.isEmpty() && _normalizeTitleKey(on) == key) {
            qDebug() << "[AxisRouter] QAction matched by objectName:" << on;
            _appActionCache.insert(key, a);
            return a;
        }
    }

    qDebug() << "[AxisRouter] QAction not found for title:" << actionTitle;
    return nullptr;
}

bool AxisActionRouter::_tryTriggerViaAppActions(const QString& actionTitle) const
{
    qDebug() << "[AxisRouter] try trigger app action:" << actionTitle;

    if (actionTitle.trimmed().isEmpty()) return false;

    QAction* qa = _findAppQActionByTitle(actionTitle);
    if (!qa) {
        qDebug() << "[AxisRouter] QAction not found in app";
        return false;
    }

    qDebug() << "[AxisRouter] triggering QAction";
    QMetaObject::invokeMethod(qa, "trigger", Qt::QueuedConnection);
    return true;
}

QObject* AxisActionRouter::_assignableActionObjectAt(int idx) const
{
    qDebug() << "[AxisRouter] get assignable action object index:" << idx;

    if (!_js || idx < 0) return nullptr;

    const QVariant v = _js->property("assignableActions");
    if (v.isValid()) {
        if (QObject* modelObj = v.value<QObject*>()) {

            QVariant row;

            if (QMetaObject::invokeMethod(modelObj, "get",
                                          Q_RETURN_ARG(QVariant, row),
                                          Q_ARG(int, idx))) {

                if (QObject* o = row.value<QObject*>()) {
                    qDebug() << "[AxisRouter] action object found";
                    return o;
                }

                const QVariantMap m = row.toMap();
                if (!m.isEmpty()) {

                    static const char* kKeys[] = { "action", "qAction", "qtAction", "object", "obj" };

                    for (const char* k : kKeys) {
                        const QVariant mv = m.value(QString::fromLatin1(k));

                        if (QObject* o2 = mv.value<QObject*>()) {
                            qDebug() << "[AxisRouter] action object found via key:" << k;
                            return o2;
                        }
                    }
                }
            }
        }
    }

    QQmlListReference list(_js, "assignableActions");

    if (list.isValid() && idx < list.count()) {
        qDebug() << "[AxisRouter] action object found via QQmlListReference";
        return list.at(idx);
    }

    qDebug() << "[AxisRouter] assignable action object not found";
    return nullptr;
}

bool AxisActionRouter::_tryTriggerViaJoystickActions(const QString& actionTitle)
{
    qDebug() << "[AxisRouter] try joystick action:" << actionTitle;

    if (!_js) return false;

    const QString want = actionTitle.trimmed();
    if (want.isEmpty()) return false;

    const QStringList titles = _variantToStringList(_js->property("assignableActionTitles"));

    if (titles.isEmpty()) {
        qDebug() << "[AxisRouter] no joystick titles found, fallback to app actions";
        return _tryTriggerViaAppActions(want);
    }

    int idx = -1;

    for (int i = 0; i < titles.size(); ++i) {
        if (titles[i].compare(want, Qt::CaseInsensitive) == 0) {
            idx = i;
            break;
        }
    }

    if (idx < 0) {
        qDebug() << "[AxisRouter] joystick action title not matched";
        return _tryTriggerViaAppActions(want);
    }

    QObject* actObj = _assignableActionObjectAt(idx);

    if (actObj) {

        if (QAction* qa = _extractAnyQAction(actObj)) {
            qDebug() << "[AxisRouter] triggering QAction via joystick";
            QMetaObject::invokeMethod(qa, "trigger", Qt::QueuedConnection);
            return true;
        }

        static const char* kTry[] = { "trigger", "execute", "invoke", "activate" };

        for (const char* m : kTry) {
            if (QMetaObject::invokeMethod(actObj, m, Qt::QueuedConnection)) {
                qDebug() << "[AxisRouter] invoked method:" << m;
                return true;
            }
        }
    }

    return _tryTriggerViaAppActions(want);
}

bool AxisActionRouter::_trySetVehicleFlightMode(const QString& modeTitle)
{
    qDebug() << "[AxisRouter] try set flight mode:" << modeTitle;

    Vehicle* veh = _vehicle.data();
    if (!veh) return false;

    const QString mode = modeTitle.trimmed();
    if (mode.isEmpty()) return false;

    if (!veh->flightModes().contains(mode)) {
        qDebug() << "[AxisRouter] flight mode not supported:" << mode;
        return false;
    }

    QMetaObject::invokeMethod(veh, [veh, mode] {
        qDebug() << "[AxisRouter] setting flight mode:" << mode;
        veh->setFlightMode(mode);
    }, Qt::QueuedConnection);

    return true;
}

void AxisActionRouter::_triggerAction(const QString& label, int servoId, int servoPwm)
{
    qDebug() << "====================================";
    qDebug() << "[AxisRouter] Trigger Action";
    qDebug() << "label:" << label;
    qDebug() << "servoId:" << servoId;
    qDebug() << "servoPwm:" << servoPwm;

    const QString a = _normalizeStored(label);

    if (_isNoAction(a)) {
        qDebug() << "[AxisRouter] no action";
        return;
    }

    if (a.compare("Arm", Qt::CaseInsensitive) == 0) {
        qDebug() << "[AxisRouter] ARM command";
        _arm(true);
        return;
    }

    if (a.compare("Disarm", Qt::CaseInsensitive) == 0) {
        qDebug() << "[AxisRouter] DISARM command";
        _arm(false);
        return;
    }

    if (a.compare("Emergency Stop", Qt::CaseInsensitive) == 0 ||
        a.compare("EmergencyStop", Qt::CaseInsensitive) == 0) {
        qDebug() << "[AxisRouter] EMERGENCY STOP";
        _emergencyStop();
        return;
    }

    if (a.compare("Servo Control", Qt::CaseInsensitive) == 0) {
        qDebug() << "[AxisRouter] MAV_CMD_DO_SET_SERVO (183)";
        _setServo(servoId, servoPwm);
        return;
    }

    if (a.compare("Actuator Control", Qt::CaseInsensitive) == 0) {
        qDebug() << "[AxisRouter] MAV_CMD_DO_SET_ACTUATOR (187)";
        _setActuator(servoId, servoPwm);
        return;
    }

    if (_trySetVehicleFlightMode(a)) return;

    if (_tryTriggerViaJoystickActions(a)) return;

    emit requestTriggerQgcAction(a);
}

void AxisActionRouter::_arm(bool arm)
{
    qDebug() << "[AxisRouter] ARM function called:" << arm;

    Vehicle* veh = _vehicle.data();
    if (!veh) return;

    QMetaObject::invokeMethod(veh, [veh, arm] {
        qDebug() << "[AxisRouter] vehicle setArmedShowError:" << arm;
        veh->setArmedShowError(arm);
    }, Qt::QueuedConnection);
}

void AxisActionRouter::_emergencyStop()
{
    qDebug() << "[AxisRouter] EMERGENCY STOP triggered";

    Vehicle* veh = _vehicle.data();
    if (!veh) return;

    QMetaObject::invokeMethod(veh, [veh] {
        veh->emergencyStop();
    }, Qt::QueuedConnection);
}

void AxisActionRouter::_setServo(int id, int pwm)
{
    qDebug() << "[AxisRouter] SEND MAV_CMD_DO_SET_SERVO";
    qDebug() << "servo id:" << id;
    qDebug() << "pwm:" << pwm;

    Vehicle* veh = _vehicle.data();
    if (!veh) return;

    veh->sendMavCommand(
        veh->defaultComponentId(),
        static_cast<MAV_CMD>(183),
        true,
        static_cast<float>(id),
        static_cast<float>(pwm),
        0,0,0,0,0);
}

void AxisActionRouter::_setActuator(int index, int rawValue)
{
    qDebug() << "========== SEND MAV_CMD 187 ==========";
    qDebug() << "index:" << index;
    qDebug() << "rawValue:" << rawValue;

    Vehicle* veh = _vehicle.data();
    if (!veh) return;

    float scaled = 0.0f;

    if (rawValue > 500) {
        scaled = (static_cast<float>(rawValue) - 1500.0f) / 500.0f;
    } else {
        scaled = static_cast<float>(rawValue);
    }

    if (scaled > 1.0f) scaled = 1.0f;
    if (scaled < -1.0f) scaled = -1.0f;

    qDebug() << "scaled value:" << scaled;

    const float nan = qQNaN();

    float p1 = nan, p2 = nan, p3 = nan, p4 = nan, p5 = nan, p6 = nan;

    switch (index) {
        case 1: p1 = scaled; break;
        case 2: p2 = scaled; break;
        case 3: p3 = scaled; break;
        case 4: p4 = scaled; break;
        case 5: p5 = scaled; break;
        case 6: p6 = scaled; break;
        default: p1 = scaled; break;
    }

    qDebug() << "params:"
             << p1 << p2 << p3 << p4 << p5 << p6;

    veh->sendMavCommand(
        veh->defaultComponentId(),
        static_cast<MAV_CMD>(187),
        false,
        p1,p2,p3,p4,p5,p6,
        0.0f);

    qDebug() << "[AxisRouter] MAV_CMD 187 SENT";
}

bool AxisActionRouter::_isVehicleFlightModeTitle(const QString& modeTitle) const
{
    Vehicle* veh = _vehicle.data();
    if (!veh) return false;

    const QString mode = modeTitle.trimmed();

    if (mode.isEmpty()) return false;

    return veh->flightModes().contains(mode);
}
