#include "AxisActionRouter.h"
#include "AxisActionRouterCommon.h"

#include <QtCore/QDateTime>
#include <algorithm>

int AxisActionRouter::calibratedPositions() const
{
    return _positionsCount(_calCenters, _calThresholds);
}

QVariantList AxisActionRouter::calibratedCenters() const
{
    QVariantList out;
    out.reserve(_calCenters.size());
    for (float c : _calCenters) out << c;
    return out;
}

QVariantList AxisActionRouter::calibratedThresholds() const
{
    QVariantList out;
    out.reserve(_calThresholds.size());
    for (float t : _calThresholds) out << t;
    return out;
}

void AxisActionRouter::startCalibration()
{
    if (_calibrating) return;

    _calibrating = true;
    _win.clear();
    _stableSamples.clear();

    _calCenters.clear();
    _calThresholds.clear();

    _pendingActions.clear();

    _lastStableCommitMs = 0;
    _lastStableCommitV  = 999.f;

    _calHint = tr("Calibrating… Move the switch to each position and pause briefly, then press Stop.");
    emit calibratingChanged();
    emit calibrationChanged();
}

void AxisActionRouter::stopCalibration()
{
    if (!_calibrating) return;
    _calibrating = false;

    _finalizeCalibrationFromSamples();

    if (_calCenters.isEmpty()) {
        emit calibratingChanged();
        emit calibrationChanged();
        _updateRepeatTimerRunning();
        return;
    }

    const int positionsNew = _positionsCount(_calCenters, _calThresholds);

    StoredMapping* m = _findMapping(_selectedAxis);
    if (!m) {
        StoredMapping nm;
        nm.axis       = _selectedAxis;
        nm.centers    = _calCenters;
        nm.thresholds = _calThresholds;
        nm.actions    = _pendingActions;

        while (nm.actions.size() < positionsNew) nm.actions << "No Action";
        if (nm.actions.size() > positionsNew)    nm.actions = nm.actions.mid(0, positionsNew);

        nm.repeats = QVector<bool>(positionsNew, false);
        nm.servoIds = QVector<int>(positionsNew, 9);
        nm.servoPwms = QVector<int>(positionsNew, 1500);

        nm.stableIndex = -999;
        nm.pendingIndex = -999;
        nm.pendingSinceMs = 0;
        nm.lastFireMs = 0;
        nm.lastRepeatMs = 0;

        _stored.push_back(nm);
    } else {
        const QStringList oldActions = m->actions;
        const QVector<bool> oldRepeats = m->repeats;
        const QVector<int> oldServoIds = m->servoIds;
        const QVector<int> oldServoPwms = m->servoPwms;

        m->centers    = _calCenters;
        m->thresholds = _calThresholds;

        m->actions = oldActions;
        while (m->actions.size() < positionsNew) m->actions << "No Action";
        if (m->actions.size() > positionsNew)    m->actions = m->actions.mid(0, positionsNew);

        m->repeats = oldRepeats;
        while (m->repeats.size() < positionsNew) m->repeats.push_back(false);
        if (m->repeats.size() > positionsNew)    m->repeats = m->repeats.mid(0, positionsNew);

        m->servoIds = oldServoIds;
        while (m->servoIds.size() < positionsNew) m->servoIds.push_back(9);
        if (m->servoIds.size() > positionsNew)    m->servoIds = m->servoIds.mid(0, positionsNew);

        m->servoPwms = oldServoPwms;
        while (m->servoPwms.size() < positionsNew) m->servoPwms.push_back(1500);
        if (m->servoPwms.size() > positionsNew)    m->servoPwms = m->servoPwms.mid(0, positionsNew);

        m->stableIndex = -999;
        m->pendingIndex = -999;
        m->pendingSinceMs = 0;
        m->lastFireMs = 0;
        m->lastRepeatMs = 0;
    }

    _normalizeCardOrder();
    _rebuildSummaries();
    _saveToSettings();
    emit mappingsChanged();

    _applyMappingToUiForAxis(_selectedAxis);

    _calHint = tr("Calibration saved for Axis %1. Assign actions on the right.").arg(_selectedAxis);

    emit calibratingChanged();
    emit calibrationChanged();

    _updateRepeatTimerRunning();
}

void AxisActionRouter::clearCalibration()
{
    _calibrating = false;
    _win.clear();
    _stableSamples.clear();

    _calCenters.clear();
    _calThresholds.clear();
    _pendingActions.clear();

    _lastStableCommitMs = 0;
    _lastStableCommitV  = 999.f;

    _calHint = tr("Cleared. Pick an axis, Start Calibrate, move through positions, then Stop.");
    emit calibratingChanged();
    emit calibrationChanged();
}

void AxisActionRouter::_calibFeed(float v, qint64 nowMs)
{
    if (_desiredPositions > 0 && _stableSamples.size() >= _desiredPositions) {
        return;
    }

    const qint64 windowMs        = 350;
    const qint64 needStableMs    = 220;
    const float  stableRange     = 0.06f;
    const float  distinctEps     = 0.12f;
    const qint64 commitCooldown  = 250;

    _win.push_back({nowMs, v});
    while (!_win.isEmpty() && (nowMs - _win.front().first) > windowMs) {
        _win.removeFirst();
    }

    if (_win.isEmpty()) return;

    const qint64 span = _win.back().first - _win.front().first;
    if (span < needStableMs) return;

    float mn =  999.f, mx = -999.f, sum = 0.f;
    for (const auto& p : _win) {
        mn = std::min(mn, p.second);
        mx = std::max(mx, p.second);
        sum += p.second;
    }

    const float mean = sum / float(_win.size());
    if ((mx - mn) > stableRange) return;

    if ((nowMs - _lastStableCommitMs) < commitCooldown) return;
    if (qAbs(mean - _lastStableCommitV) < distinctEps)  return;

    _stableSamples.push_back(mean);
    _lastStableCommitMs = nowMs;
    _lastStableCommitV  = mean;

    if (_desiredPositions > 0) {
        _calHint = tr("Captured %1/%2 stable position(s). Move to the next position and pause.")
        .arg(_stableSamples.size())
            .arg(_desiredPositions);
    } else {
        _calHint = tr("Captured %1 stable position(s). Move to the next position and pause.")
        .arg(_stableSamples.size());
    }
    emit calibrationChanged();
}

void AxisActionRouter::_finalizeCalibrationFromSamples()
{
    if (_stableSamples.isEmpty()) {
        _calHint = tr("No stable positions captured. Try again: Start Calibrate, pause at each position, then Stop.");
        return;
    }

    std::sort(_stableSamples.begin(), _stableSamples.end());

    const float clusterEps = 0.12f;
    QVector<QVector<float>> clusters;
    clusters.reserve(6);

    for (float s : _stableSamples) {
        if (clusters.isEmpty()) { clusters.push_back({s}); continue; }

        float lastMean = 0.f;
        for (float x : clusters.back()) lastMean += x;
        lastMean /= float(clusters.back().size());

        if (qAbs(s - lastMean) <= clusterEps) clusters.back().push_back(s);
        else                                  clusters.push_back({s});
    }

    QVector<float> centers;
    centers.reserve(clusters.size());
    for (const auto& c : clusters) {
        float sum = 0.f;
        for (float x : c) sum += x;
        centers.push_back(sum / float(c.size()));
    }
    std::sort(centers.begin(), centers.end());

    if (_desiredPositions > 0 && centers.size() > _desiredPositions) {
        centers = centers.mid(0, _desiredPositions);
    }

    QVector<float> thresholds;
    if (centers.size() >= 2) {
        thresholds.reserve(centers.size() - 1);
        for (int i = 0; i < centers.size() - 1; ++i) {
            thresholds.push_back((centers[i] + centers[i+1]) * 0.5f);
        }
    }

    _calCenters = centers;
    _calThresholds = thresholds;

    _pendingActions.clear();
    const int pos = _positionsCount(_calCenters, _calThresholds);
    for (int i = 0; i < pos; ++i) _pendingActions << "No Action";

    if (_calCenters.size() == 2)      _calHint = tr("Detected 2 positions (2-pos).");
    else if (_calCenters.size() == 3) _calHint = tr("Detected 3 positions (3-pos).");
    else                              _calHint = tr("Detected %1 positions (zones).").arg(_calCenters.size());
}
