#include "AxisActionRouter.h"
#include "AxisActionRouterCommon.h"

#include "Joystick.h"

#include <QtCore/QDateTime>

bool AxisActionRouter::repeatForAxis(int axis, int posIndex) const
{
    for (const auto& m : _stored) {
        if (m.axis == axis) {
            if (posIndex < 0 || posIndex >= m.repeats.size()) return false;
            return m.repeats[posIndex];
        }
    }
    return false;
}

void AxisActionRouter::setRepeatForAxis(int axis, int posIndex, bool enabled)
{
    if (posIndex < 0) return;

    StoredMapping* m = _findMapping(axis);
    if (!m) return;

    const int positions = _positionsCount(m->centers, m->thresholds);

    while (m->repeats.size() < positions) m->repeats.push_back(false);
    if (m->repeats.size() > positions)    m->repeats = m->repeats.mid(0, positions);

    if (posIndex >= m->repeats.size()) return;
    if (m->repeats[posIndex] == enabled) return;

    m->repeats[posIndex] = enabled;

    _saveToSettings();
    emit mappingsChanged();

    _updateRepeatTimerRunning();
}

bool AxisActionRouter::_actionTitleCanRepeat(const QString& actionTitle) const
{
    if (!_js) return false;

    const QString a = actionTitle.trimmed();
    if (a.isEmpty() || _isNoAction(a)) return false;

    if (a.compare("Arm", Qt::CaseInsensitive) == 0)            return false;
    if (a.compare("Disarm", Qt::CaseInsensitive) == 0)         return false;
    if (a.compare("Emergency Stop", Qt::CaseInsensitive) == 0) return false;
    if (a.compare("EmergencyStop", Qt::CaseInsensitive) == 0)  return false;

    const QStringList titles = _variantToStringList(_js->property("assignableActionTitles"));
    if (titles.isEmpty()) {
        return true;
    }

    int idx = -1;
    for (int i = 0; i < titles.size(); ++i) {
        if (titles[i].compare(a, Qt::CaseInsensitive) == 0) { idx = i; break; }
    }
    if (idx < 0) {
        return true;
    }

    QObject* actObj = _assignableActionObjectAt(idx);
    if (!actObj) return true;

    const QVariant v = actObj->property("canRepeat");
    if (!v.isValid()) return true;
    return v.toBool();
}

void AxisActionRouter::_updateRepeatTimerRunning()
{
    bool anyRepeatEnabled = false;

    if (_js) {
        for (const auto& m : _stored) {
            for (bool r : m.repeats) {
                if (r) { anyRepeatEnabled = true; break; }
            }
            if (anyRepeatEnabled) break;
        }
    }

    if (!anyRepeatEnabled) {
        if (_repeatTimer.isActive()) _repeatTimer.stop();
        return;
    }

    if (!_repeatTimer.isActive()) {
        _repeatTimer.start();
    }
}

void AxisActionRouter::_onRepeatTick()
{
    if (!_js) {
        _updateRepeatTimerRunning();
        return;
    }

    const qint64 now = QDateTime::currentMSecsSinceEpoch();

    for (auto& m : _stored) {
        const int pos = (m.stableIndex == -999) ? -1 : m.stableIndex;
        if (pos < 0) continue;

        const int positions = _positionsCount(m.centers, m.thresholds);

        while (m.actions.size() < positions)  m.actions << "No Action";
        if (m.actions.size() > positions)     m.actions = m.actions.mid(0, positions);

        while (m.repeats.size() < positions)  m.repeats.push_back(false);
        if (m.repeats.size() > positions)     m.repeats = m.repeats.mid(0, positions);

        if (pos >= positions) continue;
        if (!m.repeats[pos]) continue;

        if ((now - m.lastRepeatMs) < _repeatIntervalMs) continue;

        const QString action = _normalizeStored(m.actions[pos]);
        if (_isNoAction(action)) continue;

        if (_isVehicleFlightModeTitle(action)) continue;

        if (!_actionTitleCanRepeat(action)) continue;

        m.lastRepeatMs = now;

        int sId = 9;
        int sPwm = 1500;
        if (pos < m.servoIds.size()) sId = m.servoIds[pos];
        if (pos < m.servoPwms.size()) sPwm = m.servoPwms[pos];

        _triggerAction(action, sId, sPwm);
    }

    _updateRepeatTimerRunning();
}
