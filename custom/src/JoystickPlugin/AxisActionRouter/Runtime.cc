#include "AxisActionRouter.h"
#include "AxisActionRouterCommon.h"

#include <QtCore/QDateTime>

void AxisActionRouter::_autoSelectAxisIfMoved(int axis, int raw, float norm, qint64 nowMs)
{
    if (!_autoSelectAxis) return;
    if (_calibrating) return;
    if (axis == _selectedAxis) return;

    if (axis < 0 || axis >= _lastAxisNorm.size()) return;

    const float prev  = _lastAxisNorm[axis];
    const float delta = qAbs(norm - prev);

    const float moveDelta   = 0.18f;
    const qint64 cooldownMs = 250;

    if (delta < moveDelta) return;
    if ((nowMs - _lastAutoPickMs) < cooldownMs) return;
    if (_lastAutoAxis == axis && (nowMs - _lastAutoPickMs) < 600) return;

    _lastAutoPickMs = nowMs;
    _lastAutoAxis   = axis;

    _selectedAxis     = axis;
    _selectedAxisRaw  = raw;
    _selectedAxisNorm = norm;

    emit selectedAxisChanged();
    emit selectedAxisValueChanged();

    _applyMappingToUiForAxis(_selectedAxis);
}

void AxisActionRouter::_onAxisValueChanged(int axis, int value)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const float  v   = _norm(value);

    if (axis >= 0 && axis < _lastAxisNorm.size()) {
        _autoSelectAxisIfMoved(axis, value, v, now);
        _lastAxisNorm[axis] = v;
    }

    if (axis == _selectedAxis) {
        _selectedAxisRaw  = value;
        _selectedAxisNorm = v;
        emit selectedAxisValueChanged();

        if (_calibrating) _calibFeed(v, now);
    }

    const qint64 stableMs  = 180;
    const qint64 minGapMs  = 250;

    for (auto& m : _stored) {
        if (m.axis != axis) continue;
        if (m.centers.isEmpty()) continue;

        // --- FIX: single-position mapping should be active only near calibrated center
        int idxRaw = -1;
        const int posCount = _positionsCount(m.centers, m.thresholds);

        if (posCount == 1 && m.centers.size() == 1) {
            constexpr float kSinglePosEps = 0.20f; // tune if needed (0.15..0.25)
            const float c = m.centers[0];
            idxRaw = (qAbs(v - c) <= kSinglePosEps) ? 0 : -1;
        } else {
            idxRaw = m.thresholds.isEmpty()
                         ? _nearestCenterIndex(v, m.centers)
                         : _indexFromThresholds(v, m.thresholds);
        }

        const int prevStable = m.stableIndex;

        if (m.stableIndex == -999) {
            m.stableIndex     = idxRaw;
            m.pendingIndex    = -999;
            m.pendingSinceMs  = 0;

            if (m.stableIndex != prevStable) {
                emit axisActivePosChanged(axis, m.stableIndex);
            }
            continue;
        }

        if (idxRaw == m.stableIndex) {
            m.pendingIndex   = -999;
            m.pendingSinceMs = 0;
            continue;
        }

        if (m.pendingIndex != idxRaw) {
            m.pendingIndex   = idxRaw;
            m.pendingSinceMs = now;
            continue;
        }

        if ((now - m.pendingSinceMs) < stableMs) continue;

        m.stableIndex     = idxRaw;
        m.pendingIndex    = -999;
        m.pendingSinceMs  = 0;

        if (m.stableIndex != prevStable) {
            emit axisActivePosChanged(axis, m.stableIndex);
        }

        if (idxRaw < 0) continue;

        if ((now - m.lastFireMs) < minGapMs) continue;
        m.lastFireMs = now;

        const QString action =
            (idxRaw >= 0 && idxRaw < m.actions.size())
                ? _normalizeStored(m.actions[idxRaw])
                : QStringLiteral("No Action");

        _triggerAction(action);
    }
}

int AxisActionRouter::activePosForAxis(int axis) const
{
    for (const auto& m : _stored) {
        if (m.axis == axis) {
            return (m.stableIndex == -999) ? -1 : m.stableIndex;
        }
    }
    return -1;
}

void AxisActionRouter::emitActivePositionSnapshot()
{
    for (const auto& m : _stored) {
        const int pos = (m.stableIndex == -999) ? -1 : m.stableIndex;
        emit axisActivePosChanged(m.axis, pos);
    }
}