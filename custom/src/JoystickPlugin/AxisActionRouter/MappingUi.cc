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

void AxisActionRouter::removeMapping(int axis)
{
    for (int i = 0; i < _stored.size(); ++i) {
        if (_stored[i].axis == axis) {
            _stored.removeAt(i);
            _normalizeCardOrder();
            _rebuildSummaries();
            emit mappingsChanged();
            _saveToSettings();
            _updateRepeatTimerRunning();
            return;
        }
    }
}

void AxisActionRouter::clearAllMappings()
{
    _stored.clear();
    _mappingSummaries.clear();
    _cardOrderAxes.clear();
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