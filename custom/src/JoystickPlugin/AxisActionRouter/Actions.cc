#include "AxisActionRouter.h"
#include "AxisActionRouterCommon.h"

#include "Joystick.h"
#include "Vehicle.h"

#include <QtCore/QMetaObject>
#include <QtCore/QMetaProperty>
#include <QtCore/QCoreApplication>

#include <QtQml/QQmlListReference>
#include <QtGui/QAction>

static QAction* _extractAnyQAction(QObject* obj)
{
    if (!obj) return nullptr;

    if (auto* qa = qobject_cast<QAction*>(obj)) return qa;

    static const char* kProps[] = { "action", "qAction", "qtAction" };
    for (const char* p : kProps) {
        const QVariant v = obj->property(p);
        if (!v.isValid()) continue;

        if (auto* qa2 = v.value<QAction*>()) return qa2;

        if (QObject* o = v.value<QObject*>()) {
            if (auto* qa3 = qobject_cast<QAction*>(o)) return qa3;
        }
    }

    const QMetaObject* mo = obj->metaObject();
    for (int i = 0; i < mo->propertyCount(); ++i) {
        const QMetaProperty p = mo->property(i);
        if (!p.isReadable()) continue;

        const QVariant v = obj->property(p.name());
        if (auto* qa4 = v.value<QAction*>()) return qa4;

        if (QObject* o = v.value<QObject*>()) {
            if (auto* qa5 = qobject_cast<QAction*>(o)) return qa5;
        }
    }

    return nullptr;
}

QAction* AxisActionRouter::_findAppQActionByTitle(const QString& actionTitle) const
{
    const QString key = _normalizeTitleKey(actionTitle);
    if (key.isEmpty()) return nullptr;

    const QPointer<QAction> cached = _appActionCache.value(key);
    if (cached) return cached.data();

    const QList<QAction*> all = qApp ? qApp->findChildren<QAction*>() : QList<QAction*>();
    for (QAction* a : all) {
        if (!a) continue;

        const QString txt = _cleanActionText(a->text());
        if (!txt.isEmpty() && _normalizeTitleKey(txt) == key) {
            _appActionCache.insert(key, a);
            return a;
        }

        const QString on = a->objectName().trimmed();
        if (!on.isEmpty() && _normalizeTitleKey(on) == key) {
            _appActionCache.insert(key, a);
            return a;
        }
    }

    return nullptr;
}

bool AxisActionRouter::_tryTriggerViaAppActions(const QString& actionTitle) const
{
    if (actionTitle.trimmed().isEmpty()) return false;
    QAction* qa = _findAppQActionByTitle(actionTitle);
    if (!qa) return false;

    QMetaObject::invokeMethod(qa, "trigger", Qt::QueuedConnection);
    return true;
}

QObject* AxisActionRouter::_assignableActionObjectAt(int idx) const
{
    if (!_js || idx < 0) return nullptr;

    const QVariant v = _js->property("assignableActions");
    if (v.isValid()) {
        if (QObject* modelObj = v.value<QObject*>()) {
            QVariant row;
            if (QMetaObject::invokeMethod(modelObj, "get",
                                          Q_RETURN_ARG(QVariant, row),
                                          Q_ARG(int, idx))) {
                if (QObject* o = row.value<QObject*>()) return o;

                const QVariantMap m = row.toMap();
                if (!m.isEmpty()) {
                    static const char* kKeys[] = { "action", "qAction", "qtAction", "object", "obj" };
                    for (const char* k : kKeys) {
                        const QVariant mv = m.value(QString::fromLatin1(k));
                        if (QObject* o2 = mv.value<QObject*>()) return o2;
                    }
                }
            }
        }
    }

    QQmlListReference list(_js, "assignableActions");
    if (list.isValid() && idx < list.count()) {
        return list.at(idx);
    }

    return nullptr;
}

bool AxisActionRouter::_tryTriggerViaJoystickActions(const QString& actionTitle)
{
    if (!_js) return false;

    const QString want = actionTitle.trimmed();
    if (want.isEmpty()) return false;

    const QStringList titles = _variantToStringList(_js->property("assignableActionTitles"));
    if (titles.isEmpty()) {
        return _tryTriggerViaAppActions(want);
    }

    int idx = -1;
    for (int i = 0; i < titles.size(); ++i) {
        if (titles[i].compare(want, Qt::CaseInsensitive) == 0) { idx = i; break; }
    }
    if (idx < 0) {
        return _tryTriggerViaAppActions(want);
    }

    QObject* actObj = _assignableActionObjectAt(idx);

    if (actObj) {
        if (QAction* qa = _extractAnyQAction(actObj)) {
            QMetaObject::invokeMethod(qa, "trigger", Qt::QueuedConnection);
            return true;
        }

        static const char* kTry[] = { "trigger", "execute", "invoke", "activate" };
        for (const char* m : kTry) {
            if (QMetaObject::invokeMethod(actObj, m, Qt::QueuedConnection)) return true;
        }
    }

    return _tryTriggerViaAppActions(want);
}

bool AxisActionRouter::_trySetVehicleFlightMode(const QString& modeTitle)
{
    Vehicle* veh = _vehicle.data();
    if (!veh) return false;

    const QString mode = modeTitle.trimmed();
    if (mode.isEmpty()) return false;

    if (!veh->flightModes().contains(mode)) {
        return false;
    }

    QMetaObject::invokeMethod(veh, [veh, mode] {
        veh->setFlightMode(mode);
    }, Qt::QueuedConnection);

    return true;
}

void AxisActionRouter::_triggerAction(const QString& label)
{
    const QString a = _normalizeStored(label);
    if (_isNoAction(a)) return;

    if (a.compare("Arm", Qt::CaseInsensitive) == 0)            { _arm(true);  return; }
    if (a.compare("Disarm", Qt::CaseInsensitive) == 0)         { _arm(false); return; }
    if (a.compare("Emergency Stop", Qt::CaseInsensitive) == 0) { _emergencyStop(); return; }
    if (a.compare("EmergencyStop",  Qt::CaseInsensitive) == 0) { _emergencyStop(); return; }

    if (_trySetVehicleFlightMode(a)) return;
    if (_tryTriggerViaJoystickActions(a)) return;

    emit requestTriggerQgcAction(a);
}

void AxisActionRouter::_arm(bool arm)
{
    Vehicle* veh = _vehicle.data();
    if (!veh) return;

    QMetaObject::invokeMethod(veh, [veh, arm] {
        veh->setArmedShowError(arm);
    }, Qt::QueuedConnection);
}

void AxisActionRouter::_emergencyStop()
{
    Vehicle* veh = _vehicle.data();
    if (!veh) return;

    QMetaObject::invokeMethod(veh, [veh] {
        veh->emergencyStop();
    }, Qt::QueuedConnection);
}

bool AxisActionRouter::_isVehicleFlightModeTitle(const QString& modeTitle) const
{
    Vehicle* veh = _vehicle.data();
    if (!veh) return false;
    const QString mode = modeTitle.trimmed();
    if (mode.isEmpty()) return false;
    return veh->flightModes().contains(mode);
}