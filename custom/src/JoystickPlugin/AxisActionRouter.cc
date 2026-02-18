#include "AxisActionRouter.h"

#include "Joystick.h"
#include "Vehicle.h"
#include "QGCLoggingCategory.h"

#include <QtCore/QDateTime>
#include <QtCore/QMetaObject>
#include <QtCore/QMetaProperty>
#include <QtCore/QSettings>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonArray>
#include <QtCore/QVariant>
#include <QtCore/QDebug>

#include <QtQml/QQmlListReference>
#include <QtGui/QAction>

#include <algorithm>
#include <limits>

QGC_LOGGING_CATEGORY(AxisActLog, "qgc.custom.axisactions")

// -------------------- small helpers (ต้องอยู่ก่อน member funcs ที่เรียกใช้) --------------------
static bool _isNoAction(QString a)
{
    a = a.trimmed();
    return a.isEmpty()
           || a.compare("No Action", Qt::CaseInsensitive) == 0
           || a.compare("None",      Qt::CaseInsensitive) == 0;
}

static QString _normalizeStored(QString a)
{
    a = a.trimmed();
    return _isNoAction(a) ? QStringLiteral("No Action") : a;
}

static int _positionsCount(const QVector<float>& centers, const QVector<float>& thresholds)
{
    return thresholds.isEmpty() ? centers.size() : (thresholds.size() + 1);
}

static int _nearestCenterIndex(float v, const QVector<float>& centers)
{
    if (centers.isEmpty()) return 0;
    int best = 0;
    float bestD = std::numeric_limits<float>::max();
    for (int i = 0; i < centers.size(); ++i) {
        const float d = qAbs(v - centers[i]);
        if (d < bestD) { bestD = d; best = i; }
    }
    return best;
}

static int _indexFromThresholds(float v, const QVector<float>& th)
{
    int idx = 0;
    while (idx < th.size() && v >= th[idx]) ++idx;
    return idx;
}

static QString _propStr(QObject* o, const char* name)
{
    if (!o) return QString();
    const QVariant v = o->property(name);
    if (!v.isValid()) return QString();
    const QString s = v.toString().trimmed();
    return s.isEmpty() ? QString() : s;
}

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

// -------------------- settings --------------------
static const char* kGroup = "CustomAxisActionRouter";

// -------------------- ctor --------------------
AxisActionRouter::AxisActionRouter(QObject* parent)
    : QObject(parent)
{
    _calHint = tr("Pick an axis, press Start Calibrate, move the switch through all positions, then Stop.");
}

// -------------------- UI helpers (Right side cards) --------------------
int AxisActionRouter::positionsForAxis(int axis) const
{
    for (const auto& m : _stored) {
        if (m.axis == axis) {
            return _positionsCount(m.centers, m.thresholds);
        }
    }
    return 0;
}

QStringList AxisActionRouter::actionsForAxis(int axis) const
{
    for (const auto& m : _stored) {
        if (m.axis == axis) {
            return m.actions;
        }
    }
    return {};
}

void AxisActionRouter::setActionForAxis(int axis, int posIndex, const QString& action)
{
    if (posIndex < 0) return;

    const QString a = _normalizeStored(action);

    StoredMapping* m = _findMapping(axis);
    if (!m) return;

    const int positions = _positionsCount(m->centers, m->thresholds);
    while (m->actions.size() < positions) m->actions << "No Action";
    if (m->actions.size() > positions) m->actions = m->actions.mid(0, positions);

    if (posIndex >= m->actions.size()) return;
    if (m->actions[posIndex] == a) return;

    m->actions[posIndex] = a;

    _rebuildSummaries();
    _saveToSettings();
    emit mappingsChanged();
}

// -------------------- properties --------------------
void AxisActionRouter::setAutoSelectAxis(bool v)
{
    if (_autoSelectAxis == v) return;
    _autoSelectAxis = v;
    emit autoSelectAxisChanged();
}

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

QVariantList AxisActionRouter::mappedAxes() const
{
    QVariantList out;
    out.reserve(_stored.size());
    for (const auto& m : _stored) out << m.axis;
    return out;
}

// -------------------- persistent save/load --------------------
void AxisActionRouter::_saveToSettings() const
{
    if (_jsKey.isEmpty()) return;

    QJsonObject root;
    root["ver"] = 1;

    QJsonArray maps;
    for (const auto& m : _stored) {
        QJsonObject o;
        o["axis"] = m.axis;

        QJsonArray centers;
        for (float c : m.centers) centers.append(c);
        o["centers"] = centers;

        QJsonArray th;
        for (float t : m.thresholds) th.append(t);
        o["thresholds"] = th;

        QJsonArray actions;
        for (const QString& a : m.actions) actions.append(_normalizeStored(a));
        o["actions"] = actions;

        maps.append(o);
    }
    root["maps"] = maps;

    QSettings s;
    s.beginGroup(kGroup);
    s.setValue(_jsKey, QJsonDocument(root).toJson(QJsonDocument::Compact));
    s.endGroup();
    s.sync();
}

void AxisActionRouter::_loadFromSettings()
{
    _stored.clear();
    _mappingSummaries.clear();

    if (_jsKey.isEmpty()) {
        emit mappingsChanged();
        return;
    }

    QSettings s;
    s.beginGroup(kGroup);
    const QByteArray raw = s.value(_jsKey).toByteArray();
    s.endGroup();

    if (raw.isEmpty()) {
        emit mappingsChanged();
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(raw);
    if (!doc.isObject()) {
        emit mappingsChanged();
        return;
    }

    const QJsonObject root = doc.object();
    const QJsonArray maps  = root.value("maps").toArray();

    for (const QJsonValue& v : maps) {
        if (!v.isObject()) continue;
        const QJsonObject o = v.toObject();

        StoredMapping m;
        m.axis = o.value("axis").toInt(-1);

        for (const QJsonValue& x : o.value("centers").toArray())    m.centers.append(float(x.toDouble()));
        for (const QJsonValue& x : o.value("thresholds").toArray()) m.thresholds.append(float(x.toDouble()));
        for (const QJsonValue& x : o.value("actions").toArray())    m.actions.append(_normalizeStored(x.toString()));

        const int positions = _positionsCount(m.centers, m.thresholds);
        while (m.actions.size() < positions) m.actions << "No Action";
        if (m.actions.size() > positions) m.actions = m.actions.mid(0, positions);

        m.stableIndex = -999;
        m.pendingIndex = -999;
        m.pendingSinceMs = 0;
        m.lastFireMs = 0;

        if (m.axis < 0 || m.centers.isEmpty()) continue;

        int found = -1;
        for (int i = 0; i < _stored.size(); ++i) {
            if (_stored[i].axis == m.axis) { found = i; break; }
        }
        if (found >= 0) _stored[found] = m;
        else            _stored.append(m);
    }

    _rebuildSummaries();
    emit mappingsChanged();
    _applyMappingToUiForAxis(_selectedAxis);

    // ✅ NEW: refresh active pos snapshot for UI
    emitActivePositionSnapshot();

}

void AxisActionRouter::_rebuildSummaries()
{
    _mappingSummaries.clear();

    for (const auto& m : _stored) {
        QStringList cStr; for (float c : m.centers) cStr << QString::number(c, 'f', 3);
        QStringList tStr; for (float t : m.thresholds) tStr << QString::number(t, 'f', 3);

        _mappingSummaries << QString("Axis %1: %2-pos  centers=[%3]  thresholds=[%4]  actions=[%5]")
                                 .arg(m.axis)
                                 .arg(_positionsCount(m.centers, m.thresholds))
                                 .arg(cStr.join(", "))
                                 .arg(tStr.join(", "))
                                 .arg(m.actions.join(", "));
    }
}

// -------------------- joystick key --------------------
QString AxisActionRouter::_makeJoystickKey(Joystick* js) const
{
    if (!js) return QString();

    QString id = _propStr(js, "guid");
    if (id.isEmpty()) id = _propStr(js, "deviceGuid");
    if (id.isEmpty()) id = _propStr(js, "deviceUID");
    if (id.isEmpty()) id = _propStr(js, "uid");
    if (id.isEmpty()) id = _propStr(js, "deviceId");

    if (!id.isEmpty()) return QString("joy:%1").arg(id);

    return QString("joy:%1|a%2|b%3")
        .arg(js->name())
        .arg(js->axisCount())
        .arg(js->totalButtonCount());
}

// -------------------- wiring --------------------
void AxisActionRouter::setJoystick(QObject* joystickObj)
{
    Joystick* js = qobject_cast<Joystick*>(joystickObj);
    if (js == _js) return;

    _saveToSettings();
    _detach();
    _attach(js);

    _jsKey = _makeJoystickKey(_js);
    _loadFromSettings();
}

void AxisActionRouter::setVehicle(QObject* vehicleObj)
{
    _vehicle = qobject_cast<Vehicle*>(vehicleObj);
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

            // กันค้างกรณี joystick ถูกลบตอนถอดอุปกรณ์
    connect(_js, &QObject::destroyed, this, [this](QObject*) {
        _saveToSettings();
        _detach();
        _jsKey.clear();
        emit mappingsChanged();
    }, Qt::QueuedConnection);
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

// -------------------- values --------------------
float AxisActionRouter::_norm(int v) const
{
    float f = v / 32768.0f;
    if (f < -1.f) return -1.f;
    if (f >  1.f) return  1.f;
    return f;
}

// -------------------- calibration --------------------
void AxisActionRouter::startCalibration()
{
    if (_calibrating) return;

    _calibrating = true;
    _win.clear();
    _stableSamples.clear();

    _calCenters.clear();
    _calThresholds.clear();

    _pendingActions.clear(); // จะถูกสร้างใหม่ตอน finalize

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

            // ถ้าจับ stable ไม่ได้ -> แค่แจ้ง hint
    if (_calCenters.isEmpty()) {
        emit calibratingChanged();
        emit calibrationChanged();
        return;
    }

            // ✅ Auto-save zones into mapping (ไม่มีปุ่ม Add/Save แล้ว)
    StoredMapping* m = _findMapping(_selectedAxis);
    if (!m) {
        StoredMapping nm;
        nm.axis       = _selectedAxis;
        nm.centers    = _calCenters;
        nm.thresholds = _calThresholds;
        nm.actions    = _pendingActions;

        const int positions = _positionsCount(nm.centers, nm.thresholds);
        while (nm.actions.size() < positions) nm.actions << "No Action";
        if (nm.actions.size() > positions) nm.actions = nm.actions.mid(0, positions);

        nm.stableIndex = -999;
        nm.pendingIndex = -999;
        nm.pendingSinceMs = 0;
        nm.lastFireMs = 0;

        _stored.push_back(nm);
    } else {
        const QStringList oldActions = m->actions;

        m->centers    = _calCenters;
        m->thresholds = _calThresholds;

        const int positions = _positionsCount(m->centers, m->thresholds);
        m->actions = oldActions;
        while (m->actions.size() < positions) m->actions << "No Action";
        if (m->actions.size() > positions) m->actions = m->actions.mid(0, positions);

        m->stableIndex = -999;
        m->pendingIndex = -999;
        m->pendingSinceMs = 0;
        m->lastFireMs = 0;
    }

    _rebuildSummaries();
    _saveToSettings();
    emit mappingsChanged();

            // refresh UI state for selected axis
    _applyMappingToUiForAxis(_selectedAxis);

            // override hint ให้ชัดเจน
    _calHint = tr("Calibration saved for Axis %1. Assign actions on the right.").arg(_selectedAxis);

    emit calibratingChanged();
    emit calibrationChanged();
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

// ---- calibration helpers ----
void AxisActionRouter::_calibFeed(float v, qint64 nowMs)
{
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

    _calHint = tr("Captured %1 stable position(s). Move to the next position and pause.").arg(_stableSamples.size());
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

    QVector<float> thresholds;
    if (centers.size() >= 2) {
        thresholds.reserve(centers.size() - 1);
        for (int i = 0; i < centers.size() - 1; ++i) {
            thresholds.push_back((centers[i] + centers[i+1]) * 0.5f);
        }
    }

    _calCenters = centers;
    _calThresholds = thresholds;

            // default actions หลัง finalize
    _pendingActions.clear();
    const int pos = _positionsCount(_calCenters, _calThresholds);
    for (int i = 0; i < pos; ++i) _pendingActions << "No Action";

    if (_calCenters.size() == 2)      _calHint = tr("Detected 2 positions (2-pos).");
    else if (_calCenters.size() == 3) _calHint = tr("Detected 3 positions (3-pos).");
    else                              _calHint = tr("Detected %1 positions (zones).").arg(_calCenters.size());
}

// -------------------- auto select axis --------------------
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

// -------------------- runtime axis update + stable trigger --------------------
// void AxisActionRouter::_onAxisValueChanged(int axis, int value)
// {
//     const qint64 now = QDateTime::currentMSecsSinceEpoch();
//     const float  v   = _norm(value);

//     if (axis >= 0 && axis < _lastAxisNorm.size()) {
//         _autoSelectAxisIfMoved(axis, value, v, now);
//         _lastAxisNorm[axis] = v;
//     }

//     if (axis == _selectedAxis) {
//         _selectedAxisRaw  = value;
//         _selectedAxisNorm = v;
//         emit selectedAxisValueChanged();

//         if (_calibrating) _calibFeed(v, now);
//     }

//             // Anti-jitter
//     const qint64 stableMs  = 180;
//     const qint64 minGapMs  = 250;

//     for (auto& m : _stored) {
//         if (m.axis != axis) continue;
//         if (m.centers.isEmpty()) continue;

//         const int idxRaw = m.thresholds.isEmpty()
//                                ? _nearestCenterIndex(v, m.centers)
//                                : _indexFromThresholds(v, m.thresholds);

//         if (m.stableIndex == -999) {
//             m.stableIndex = idxRaw;
//             m.pendingIndex = -999;
//             m.pendingSinceMs = 0;
//             continue;
//         }

//         if (idxRaw == m.stableIndex) {
//             m.pendingIndex = -999;
//             m.pendingSinceMs = 0;
//             continue;
//         }

//         if (m.pendingIndex != idxRaw) {
//             m.pendingIndex = idxRaw;
//             m.pendingSinceMs = now;
//             continue;
//         }

//         if ((now - m.pendingSinceMs) < stableMs) continue;

//         m.stableIndex = idxRaw;
//         m.pendingIndex = -999;
//         m.pendingSinceMs = 0;

//         if ((now - m.lastFireMs) < minGapMs) continue;
//         m.lastFireMs = now;

//         const QString action =
//             (idxRaw >= 0 && idxRaw < m.actions.size())
//                 ? _normalizeStored(m.actions[idxRaw])
//                 : QStringLiteral("No Action");

//         qWarning() << "[AXMAP]" << "axis=" << axis << "idx=" << idxRaw << "norm=" << v << "action=" << action;

//         _triggerAction(action);
//     }
// }

// -------------------- runtime axis update + stable trigger --------------------
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

            // Anti-jitter
    const qint64 stableMs  = 180;
    const qint64 minGapMs  = 250;

    for (auto& m : _stored) {
        if (m.axis != axis) continue;
        if (m.centers.isEmpty()) continue;

        const int idxRaw = m.thresholds.isEmpty()
                               ? _nearestCenterIndex(v, m.centers)
                               : _indexFromThresholds(v, m.thresholds);

        const int prevStable = m.stableIndex;   // ✅ เก็บค่าเดิมไว้เทียบ

                // init ครั้งแรก: ตั้ง stableIndex แล้ว emit ให้ UI รู้ทันที
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

                // stable เปลี่ยนตำแหน่งแล้ว
        m.stableIndex     = idxRaw;
        m.pendingIndex    = -999;
        m.pendingSinceMs  = 0;

                //  emit ก่อน minGapMs เพื่อให้ UI ติด/ดับได้แม้ action ยังไม่ยิง
        if (m.stableIndex != prevStable) {
            emit axisActivePosChanged(axis, m.stableIndex);
        }

                // จำกัดความถี่การยิง action
        if ((now - m.lastFireMs) < minGapMs) continue;
        m.lastFireMs = now;

        const QString action =
            (idxRaw >= 0 && idxRaw < m.actions.size())
                ? _normalizeStored(m.actions[idxRaw])
                : QStringLiteral("No Action");

        qWarning() << "[AXMAP]" << "axis=" << axis << "idx=" << idxRaw << "norm=" << v << "action=" << action;

        _triggerAction(action);
    }
}


AxisActionRouter::StoredMapping* AxisActionRouter::_findMapping(int axis)
{
    for (auto& m : _stored) {
        if (m.axis == axis) return &m;
    }
    return nullptr;
}

void AxisActionRouter::_applyMappingToUiForAxis(int axis)
{
    if (auto* m = _findMapping(axis)) {
        _calCenters     = m->centers;
        _calThresholds  = m->thresholds;

                // sync default pending actions = stored actions
        _pendingActions = m->actions;

        const int positions = _positionsCount(_calCenters, _calThresholds);
        while (_pendingActions.size() < positions) _pendingActions << "No Action";
        if (_pendingActions.size() > positions) _pendingActions = _pendingActions.mid(0, positions);

        _calHint = tr("Loaded saved mapping for Axis %1.").arg(axis);
    } else {
        _calCenters.clear();
        _calThresholds.clear();
        _pendingActions.clear();
        _calHint = tr("No saved mapping for Axis %1. Calibrate and store if needed.").arg(axis);
    }

    emit calibrationChanged();
}

void AxisActionRouter::removeMapping(int axis)
{
    for (int i = 0; i < _stored.size(); ++i) {
        if (_stored[i].axis == axis) {
            _stored.removeAt(i);
            _rebuildSummaries();
            emit mappingsChanged();
            _saveToSettings();
            return;
        }
    }
}

void AxisActionRouter::clearAllMappings()
{
    _stored.clear();
    _mappingSummaries.clear();
    emit mappingsChanged();
    _saveToSettings();
}

// -------------------- action dispatch --------------------
bool AxisActionRouter::_trySetVehicleFlightMode(const QString& modeTitle)
{
    if (!_vehicle) return false;

    const QString mode = modeTitle.trimmed();
    if (mode.isEmpty()) return false;

    if (!_vehicle->flightModes().contains(mode)) {
        return false;
    }

    QMetaObject::invokeMethod(_vehicle, [veh=_vehicle, mode] {
        veh->setFlightMode(mode);
    }, Qt::QueuedConnection);

    return true;
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


QObject* AxisActionRouter::_assignableActionObjectAt(int idx) const
{
    if (!_js) return nullptr;
    if (idx < 0) return nullptr;

    const QVariant v = _js->property("assignableActions");
    if (v.isValid()) {
        QObject* modelObj = v.value<QObject*>();
        if (modelObj) {
            QObject* actObj = nullptr;

            if (QMetaObject::invokeMethod(modelObj, "get",
                                          Q_RETURN_ARG(QObject*, actObj),
                                          Q_ARG(int, idx))) {
                return actObj;
            }

            actObj = nullptr;
            if (QMetaObject::invokeMethod(modelObj, "at",
                                          Q_RETURN_ARG(QObject*, actObj),
                                          Q_ARG(int, idx))) {
                return actObj;
            }

            const int count = modelObj->property("count").toInt();
            if (count > 0 && idx < count) {
                actObj = nullptr;
                if (QMetaObject::invokeMethod(modelObj, "get",
                                              Q_RETURN_ARG(QObject*, actObj),
                                              Q_ARG(int, idx))) {
                    return actObj;
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

    const QStringList titles = _js->property("assignableActionTitles").toStringList();
    if (titles.isEmpty()) return false;

    int idx = -1;
    for (int i = 0; i < titles.size(); ++i) {
        if (titles[i].compare(want, Qt::CaseInsensitive) == 0) { idx = i; break; }
    }
    if (idx < 0) return false;

    QObject* actObj = _assignableActionObjectAt(idx);
    if (!actObj) return false;

    if (QAction* qa = _extractAnyQAction(actObj)) {
        QMetaObject::invokeMethod(qa, "trigger", Qt::QueuedConnection);
        return true;
    }

    static const char* kTry[] = { "trigger", "execute", "invoke", "activate" };
    for (const char* m : kTry) {
        if (QMetaObject::invokeMethod(actObj, m, Qt::QueuedConnection)) {
            return true;
        }
    }

    qWarning() << "[AXMAP] cannot trigger action:" << want
               << "class=" << actObj->metaObject()->className();
    return false;
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

void AxisActionRouter::emitActivePositionSnapshot()
{
    // ยิงสัญญาณให้ QML เติม map ได้ทันที แม้ไม่มีการขยับแกนตอนกลับหน้า
    for (const auto& m : _stored) {
        const int pos = (m.stableIndex == -999) ? -1 : m.stableIndex;
        emit axisActivePosChanged(m.axis, pos);
    }
}


void AxisActionRouter::_arm(bool arm)
{
    if (!_vehicle) return;
    QMetaObject::invokeMethod(_vehicle, [veh=_vehicle, arm]{
        veh->setArmedShowError(arm);
    }, Qt::QueuedConnection);
}

void AxisActionRouter::_emergencyStop()
{
    if (!_vehicle) return;
    QMetaObject::invokeMethod(_vehicle, [veh=_vehicle]{
        veh->emergencyStop();
    }, Qt::QueuedConnection);
}
