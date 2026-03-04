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
    Joystick* js = qobject_cast<Joystick*>(joystickObj);
    if (js == _js.data()) return;

    _saveToSettings();
    _detach();
    _attach(js);

    _jsKey = _makeJoystickKey(_js);
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
        // IMPORTANT: clear pointer immediately to avoid use-after-free in queued axis events
        _saveToSettings();
        _js = nullptr;
        _detach();
        _jsKey.clear();
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
