#include "AxisActionRouter.h"
#include "AxisActionRouterCommon.h"

#include <QtCore/QSettings>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonArray>

static const char* kGroup = "CustomAxisActionRouter";

static QString _safeKeyPart(QString s)
{
    s = s.trimmed();
    // Make it safer as a settings key
    s.replace('/',  '_');
    s.replace('\\', '_');
    s.replace(':',  '_');
    s.replace('|',  '_');
    return s;
}

static QStringList _candidateKeysForLoad(Joystick* js)
{
    QStringList keys;
    if (!js) return keys;

            // New stable key (name-only)
    const QString name = _safeKeyPart(js->name());
    if (!name.isEmpty()) {
        keys << QString("joy:name:%1").arg(name);
    }

            // Legacy id-based keys (older builds)
    const char* props[] = { "guid", "deviceGuid", "deviceUID", "uid", "deviceId" };
    for (const char* p : props) {
        const QString id = _propStr(js, p);
        if (!id.isEmpty()) {
            keys << QString("joy:%1").arg(id);
        }
    }

            // Legacy fallback key that included counts (can change, but try anyway for migration)
    keys << QString("joy:%1|a%2|b%3")
                .arg(js->name())
                .arg(js->axisCount())
                .arg(js->totalButtonCount());

    keys.removeDuplicates();
    return keys;
}

void AxisActionRouter::_saveToSettings() const
{
    if (_jsKey.isEmpty()) return;

    QJsonObject root;
    root["ver"] = 2;

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

        QJsonArray rep;
        for (bool r : m.repeats) rep.append(r);
        o["repeat"] = rep;

        maps.append(o);
    }
    root["maps"] = maps;

    QJsonObject ui;
    QJsonObject axisNames;
    for (auto it = _axisNames.constBegin(); it != _axisNames.constEnd(); ++it) {
        axisNames[QString::number(it.key())] = it.value();
    }
    ui["axisNames"] = axisNames;

    QJsonArray order;
    for (int a : _cardOrderAxes) order.append(a);
    ui["cardOrder"] = order;

    root["ui"] = ui;

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
    _axisNames.clear();
    _cardOrderAxes.clear();

    if (_jsKey.isEmpty()) {
        emit mappingsChanged();
        _updateRepeatTimerRunning();
        return;
    }

    QByteArray raw;
    QString usedKey;

    QSettings s;
    s.beginGroup(kGroup);

            // Try current key first
    raw = s.value(_jsKey).toByteArray();
    usedKey = _jsKey;

            // If not found, try legacy keys and migrate
    if (raw.isEmpty() && _js) {
        const QStringList candidates = _candidateKeysForLoad(_js.data());
        for (const QString& k : candidates) {
            if (k == _jsKey) continue;
            const QByteArray r2 = s.value(k).toByteArray();
            if (!r2.isEmpty()) {
                raw = r2;
                usedKey = k;
                break;
            }
        }
    }

    s.endGroup();

    if (raw.isEmpty()) {
        emit mappingsChanged();
        _updateRepeatTimerRunning();
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(raw);
    if (!doc.isObject()) {
        emit mappingsChanged();
        _updateRepeatTimerRunning();
        return;
    }

    const QJsonObject root = doc.object();

    const QJsonObject ui = root.value("ui").toObject();
    const QJsonObject axisNames = ui.value("axisNames").toObject();
    for (auto it = axisNames.begin(); it != axisNames.end(); ++it) {
        bool ok = false;
        const int a = it.key().toInt(&ok);
        if (!ok) continue;
        _axisNames[a] = it.value().toString();
    }

    const QJsonArray order = ui.value("cardOrder").toArray();
    for (const QJsonValue& v : order) {
        if (!v.isDouble()) continue;
        _cardOrderAxes.push_back(v.toInt());
    }

    const QJsonArray maps = root.value("maps").toArray();
    for (const QJsonValue& v : maps) {
        if (!v.isObject()) continue;
        const QJsonObject o = v.toObject();

        StoredMapping m;
        m.axis = o.value("axis").toInt(-1);

        for (const QJsonValue& x : o.value("centers").toArray())    m.centers.append(float(x.toDouble()));
        for (const QJsonValue& x : o.value("thresholds").toArray()) m.thresholds.append(float(x.toDouble()));
        for (const QJsonValue& x : o.value("actions").toArray())    m.actions.append(_normalizeStored(x.toString()));
        for (const QJsonValue& x : o.value("repeat").toArray())     m.repeats.append(x.toBool(false));

        const int positions = _positionsCount(m.centers, m.thresholds);

        while (m.actions.size() < positions) m.actions << "No Action";
        if (m.actions.size() > positions)    m.actions = m.actions.mid(0, positions);

        while (m.repeats.size() < positions) m.repeats.push_back(false);
        if (m.repeats.size() > positions)    m.repeats = m.repeats.mid(0, positions);

        m.stableIndex = -999;
        m.pendingIndex = -999;
        m.pendingSinceMs = 0;
        m.lastFireMs = 0;
        m.lastRepeatMs = 0;

        if (m.axis < 0 || m.centers.isEmpty()) continue;

        int found = -1;
        for (int i = 0; i < _stored.size(); ++i) {
            if (_stored[i].axis == m.axis) { found = i; break; }
        }
        if (found >= 0) _stored[found] = m;
        else            _stored.append(m);
    }

    _normalizeCardOrder();
    _rebuildSummaries();
    emit mappingsChanged();

    _applyMappingToUiForAxis(_selectedAxis);
    emitActivePositionSnapshot();

    _updateRepeatTimerRunning();

            // Migrate from legacy key to current key
    if (!usedKey.isEmpty() && usedKey != _jsKey) {
        _saveToSettings();
    }
}

QString AxisActionRouter::_makeJoystickKey(Joystick* js) const
{
    if (!js) return QString();

            // IMPORTANT: stable key (do NOT include axisCount/buttonCount)
    const QString name = _safeKeyPart(js->name());
    if (name.isEmpty()) return QStringLiteral("joy:name:unknown");

    return QString("joy:name:%1").arg(name);
}
