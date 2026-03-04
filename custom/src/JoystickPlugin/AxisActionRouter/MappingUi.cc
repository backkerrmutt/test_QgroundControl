#include "AxisActionRouter.h"
#include "AxisActionRouterCommon.h"

#include <QtCore/QVariant>

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
    if (m->actions.size() > positions)    m->actions = m->actions.mid(0, positions);

    while (m->repeats.size() < positions) m->repeats.push_back(false);
    if (m->repeats.size() > positions)    m->repeats = m->repeats.mid(0, positions);

    if (posIndex >= m->actions.size()) return;
    if (m->actions[posIndex] == a) return;

    m->actions[posIndex] = a;

    _rebuildSummaries();
    _saveToSettings();
    emit mappingsChanged();

    _updateRepeatTimerRunning();
}

// -----------------------------------------------------
// ฟังก์ชันสำหรับ UI ของ Servo Control
// -----------------------------------------------------
int AxisActionRouter::servoIdForAxis(int axis, int posIndex) const
{
    for (const auto& m : _stored) {
        if (m.axis == axis) {
            if (posIndex >= 0 && posIndex < m.servoIds.size()) return m.servoIds[posIndex];
        }
    }
    return 9; // ค่า Default
}

void AxisActionRouter::setServoIdForAxis(int axis, int posIndex, int id)
{
    if (posIndex < 0) return;
    StoredMapping* m = _findMapping(axis);
    if (!m) return;

    const int positions = _positionsCount(m->centers, m->thresholds);
    while (m->servoIds.size() < positions) m->servoIds.push_back(9);
    if (m->servoIds.size() > positions) m->servoIds = m->servoIds.mid(0, positions);

    if (posIndex >= m->servoIds.size()) return;
    if (m->servoIds[posIndex] == id) return;

    m->servoIds[posIndex] = id;
    _saveToSettings();
    // ใช้ signal เฉพาะเพื่อไม่ให้ QML recompute actionCombo.currentIndex
    emit servoParamsChanged(axis, posIndex);
}

int AxisActionRouter::servoPwmForAxis(int axis, int posIndex) const
{
    for (const auto& m : _stored) {
        if (m.axis == axis) {
            if (posIndex >= 0 && posIndex < m.servoPwms.size()) return m.servoPwms[posIndex];
        }
    }
    return 1500; // ค่า Default PWM
}

void AxisActionRouter::setServoPwmForAxis(int axis, int posIndex, int pwm)
{
    if (posIndex < 0) return;
    StoredMapping* m = _findMapping(axis);
    if (!m) return;

    const int positions = _positionsCount(m->centers, m->thresholds);
    while (m->servoPwms.size() < positions) m->servoPwms.push_back(1500);
    if (m->servoPwms.size() > positions) m->servoPwms = m->servoPwms.mid(0, positions);

    if (posIndex >= m->servoPwms.size()) return;
    if (m->servoPwms[posIndex] == pwm) return;

    m->servoPwms[posIndex] = pwm;
    _saveToSettings();
    // ใช้ signal เฉพาะเพื่อไม่ให้ QML recompute actionCombo.currentIndex
    emit servoParamsChanged(axis, posIndex);
}
// -----------------------------------------------------

QVariantList AxisActionRouter::mappedAxes() const
{
    return _mappedAxesOrdered();
}

QString AxisActionRouter::axisLabel(int axis) const
{
    const QString name = _axisNames.value(axis).trimmed();
    if (!name.isEmpty()) return name;
    return QStringLiteral("Axis %1").arg(axis);
}

void AxisActionRouter::setAxisLabel(int axis, const QString& label)
{
    const QString v = label.trimmed();
    if (v.isEmpty()) {
        _axisNames.remove(axis);
    } else {
        _axisNames[axis] = v;
    }
    _saveToSettings();
    emit mappingsChanged();
}

void AxisActionRouter::clearAxisLabel(int axis)
{
    if (_axisNames.contains(axis)) {
        _axisNames.remove(axis);
        _saveToSettings();
        emit mappingsChanged();
    }
}

QVariantList AxisActionRouter::cardOrder() const
{
    QVariantList out;
    out.reserve(_cardOrderAxes.size());
    for (int a : _cardOrderAxes) out << a;
    return out;
}

void AxisActionRouter::setCardOrder(const QVariantList& order)
{
    QVector<int> next;
    next.reserve(order.size());
    for (const QVariant& v : order) {
        bool ok = false;
        const int a = v.toInt(&ok);
        if (!ok) continue;
        if (!next.contains(a)) next.push_back(a);
    }
    _cardOrderAxes = next;
    _normalizeCardOrder();
    _saveToSettings();
    emit mappingsChanged();
}

void AxisActionRouter::_normalizeCardOrder()
{
    QVector<int> mapped;
    mapped.reserve(_stored.size());
    for (const auto& m : _stored) mapped.push_back(m.axis);

    QVector<int> cleaned;
    cleaned.reserve(_cardOrderAxes.size());
    for (int a : _cardOrderAxes) {
        if (mapped.contains(a) && !cleaned.contains(a)) cleaned.push_back(a);
    }
    for (int a : mapped) {
        if (!cleaned.contains(a)) cleaned.push_back(a);
    }
    _cardOrderAxes = cleaned;
}

QVariantList AxisActionRouter::_mappedAxesOrdered() const
{
    QVector<int> mapped;
    mapped.reserve(_stored.size());
    for (const auto& m : _stored) mapped.push_back(m.axis);

    QVector<int> order = _cardOrderAxes;
    if (order.isEmpty()) order = mapped;

    QVariantList out;
    out.reserve(mapped.size());

    for (int a : order) {
        if (mapped.contains(a)) out << a;
    }
    for (int a : mapped) {
        if (!out.contains(a)) out << a;
    }
    return out;
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

// ✅ แก้บัค: สั่งให้เคลียร์ชื่อแกน และรีเซ็ต UI ให้กลับเป็น Default เมื่อกด Remove
void AxisActionRouter::removeMapping(int axis)
{
    bool found = false;
    for (int i = 0; i < _stored.size(); ++i) {
        if (_stored[i].axis == axis) {
            _stored.removeAt(i);
            found = true;
            break;
        }
    }

    if (found) {
        // 1. ลบชื่อ Custom Name (เช่น คำว่า TEST) เพื่อให้กลับไปเป็นชื่อปกติ (Axis X)
        if (_axisNames.contains(axis)) {
            _axisNames.remove(axis);
        }

        _normalizeCardOrder();
        _rebuildSummaries();

                // 2. ถ้านี่คือแกนที่กำลังถูกเปิดค้างไว้ในหน้าจอซ้ายมือ (Calibration) ให้รีเซ็ตค่า UI คืนด้วย
        if (axis == _selectedAxis) {
            _applyMappingToUiForAxis(axis);
        }

        emit mappingsChanged();
        _saveToSettings();
        _updateRepeatTimerRunning();
    }
}

void AxisActionRouter::clearAllMappings()
{
    _stored.clear();
    _mappingSummaries.clear();
    _cardOrderAxes.clear();

            // เคลียร์ชื่อและ UI ทั้งหมด
    _axisNames.clear();
    _applyMappingToUiForAxis(_selectedAxis);

    emit mappingsChanged();
    _saveToSettings();
    _updateRepeatTimerRunning();
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
