#include "AxisActionRouter.h"
#include "AxisActionRouterCommon.h"

#include "Joystick.h"
#include "Vehicle.h"
#include "QGCLoggingCategory.h"

#include <QtCore/QDateTime>
#include <algorithm>

QGC_LOGGING_CATEGORY(AxisActLog, "qgc.custom.axisactions")

AxisActionRouter::AxisActionRouter(QObject* parent)
    : QObject(parent)
{
    _calHint = tr("Pick an axis, press Start Calibrate, move the switch through all positions, then Stop.");

    _repeatTimer.setInterval(_repeatIntervalMs);
    _repeatTimer.setSingleShot(false);
    connect(&_repeatTimer, &QTimer::timeout, this, &AxisActionRouter::_onRepeatTick);
}

void AxisActionRouter::setAutoSelectAxis(bool v)
{
    if (_autoSelectAxis == v) return;
    _autoSelectAxis = v;
    emit autoSelectAxisChanged();
}

void AxisActionRouter::setDesiredPositions(int v)
{
    int clamped = v;
    if (clamped < 1) clamped = 1;
    if (clamped > 3) clamped = 3;
    if (_desiredPositions == clamped) return;
    _desiredPositions = clamped;
    emit desiredPositionsChanged();
}

void AxisActionRouter::setJoystick(QObject* joystickObj)
{
    Joystick* js = joystickObj ? qobject_cast<Joystick*>(joystickObj) : nullptr;

            // Guard: null joystickObj means "no joystick" — that's valid
            // But non-null that fails cast means wrong type — treat as null
    if (joystickObj && !js) {
        qCWarning(AxisActLog) << "setJoystick: object is not a Joystick*," << joystickObj->metaObject()->className();
    }

    if (js == _js.data()) return;

            // ① Save current joystick data before switching
    _saveToSettings();
    _detach();

            // ② Set new key BEFORE attach so _loadFromSettings uses the correct key
            //    (and the destroyed-signal lambda can't race-clear it)
    _jsKey = _makeJoystickKey(js);

    _attach(js);
    _loadFromSettings();
}

void AxisActionRouter::setVehicle(QObject* vehicleObj)
{
    Vehicle* v = qobject_cast<Vehicle*>(vehicleObj);
    if (_vehicle.data() == v) {
        return;
    }
    _vehicle = v;
}

void AxisActionRouter::_attach(Joystick* js)
{
    _js = js;
    _rebuildAxisList();

    if (!_js) {
        return;
    }

    _lastAxisNorm.resize(_js->axisCount());
    std::fill(_lastAxisNorm.begin(), _lastAxisNorm.end(), 0.f);

    connect(_js, &Joystick::rawAxisValueChanged,
            this, &AxisActionRouter::_onAxisValueChanged,
            Qt::QueuedConnection);

    connect(_js, &QObject::destroyed, this, [this](QObject*) {
        // Joy object is being destroyed — handle cleanup carefully to avoid use-after-free
        _saveToSettings();
        _jsKey.clear();
        // Disconnect signals BEFORE nulling _js (otherwise disconnect(null) is a no-op)
        if (_js) disconnect(_js, nullptr, this, nullptr);
        _js = nullptr;
        // Manual inline detach (can't call _detach() because it checks _js which is now null)
        _lastAxisNorm.clear();
        _lastAutoPickMs = 0;
        _lastAutoAxis   = -1;
        _rebuildAxisList();
        emit mappingsChanged();
    }, Qt::DirectConnection);
}

void AxisActionRouter::_detach()
{
    if (_js) {
        disconnect(_js, nullptr, this, nullptr);
        _js = nullptr;
    }

    _lastAxisNorm.clear();
    _lastAutoPickMs = 0;
    _lastAutoAxis = -1;

    _rebuildAxisList();
}

void AxisActionRouter::_rebuildAxisList()
{
    QStringList list;
    const int n = _js ? _js->axisCount() : 0;
    for (int i = 0; i < n; ++i) list << QString::number(i);

    if (list != _axisList) {
        _axisList = list;
        emit axisListChanged();
    }

    if (_axisList.isEmpty()) {
        if (_selectedAxis != 0) { _selectedAxis = 0; emit selectedAxisChanged(); }
    } else {
        int clamped = _selectedAxis;
        if (clamped < 0) clamped = 0;
        if (clamped >= _axisList.size()) clamped = _axisList.size() - 1;
        if (clamped != _selectedAxis) { _selectedAxis = clamped; emit selectedAxisChanged(); }
    }
}

void AxisActionRouter::setSelectedAxis(int axis)
{
    if (_axisList.isEmpty()) {
        _selectedAxis = 0;
        emit selectedAxisChanged();
        return;
    }

    int clamped = axis;
    if (clamped < 0) clamped = 0;
    if (clamped >= _axisList.size()) clamped = _axisList.size() - 1;
    if (clamped == _selectedAxis) return;

    _selectedAxis = clamped;

    _selectedAxisRaw  = 0;
    _selectedAxisNorm = 0.f;

    emit selectedAxisChanged();
    emit selectedAxisValueChanged();

    _applyMappingToUiForAxis(_selectedAxis);
}

float AxisActionRouter::_norm(int v) const
{
    float f = v / 32768.0f;
    if (f < -1.f) return -1.f;
    if (f >  1.f) return  1.f;
    return f;
}
