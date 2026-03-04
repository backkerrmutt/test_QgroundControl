#include "AxisActionRouter.h"
#include "AxisActionRouterCommon.h"

#include <QtCore/QDateTime>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonArray>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QUrl>
#include <QtCore/QDir>
#include <QtCore/QStandardPaths>
#include <QtCore/QCoreApplication>

static QString _actionConfigDirPath()
{
    QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (docs.isEmpty()) {
        docs = QDir::homePath();
    }

    QString appName = QCoreApplication::applicationName().trimmed();
    if (appName.isEmpty()) {
        appName = QStringLiteral("QGroundControl");
    }

    const QString appDir = QDir(docs).filePath(appName);
    const QString cfgDir = QDir(appDir).filePath(QStringLiteral("ActionConfig"));
    QDir().mkpath(cfgDir);
    return cfgDir;
}

QString AxisActionRouter::_fileUrlToLocalPath(const QUrl& url)
{
    if (!url.isValid()) return QString();
    if (url.isLocalFile()) return url.toLocalFile();

    const QString s = url.toString();
    if (s.startsWith("file:", Qt::CaseInsensitive)) {
        return QUrl(s).toLocalFile();
    }
    return QString();
}

QUrl AxisActionRouter::actionConfigDirUrl() const
{
    const QString dir = _actionConfigDirPath();
    return QUrl::fromLocalFile(QDir(dir).absolutePath() + QLatin1Char('/'));
}

QString AxisActionRouter::exportProfileJson() const
{
    QJsonObject root;
    root["ver"] = 1;
    root["when"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

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

        QJsonArray sIds;
        for (int v : m.servoIds) sIds.append(v);
        o["servoIds"] = sIds;

        QJsonArray sPwms;
        for (int v : m.servoPwms) sPwms.append(v);
        o["servoPwms"] = sPwms;

        maps.append(o);
    }
    root["maps"] = maps;

    return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Indented));
}

QString AxisActionRouter::importProfileJson(const QString& jsonText)
{
    if (jsonText.trimmed().isEmpty()) return QStringLiteral("Empty JSON");

    QJsonParseError pe{};
    const QJsonDocument doc = QJsonDocument::fromJson(jsonText.toUtf8(), &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
        return QStringLiteral("JSON parse error: %1").arg(pe.errorString());
    }

    const QJsonObject root = doc.object();
    const QJsonObject ui = root.value("ui").toObject();

    const QJsonObject axisNames = ui.value("axisNames").toObject();
    QHash<int, QString> nextNames;
    for (auto it = axisNames.begin(); it != axisNames.end(); ++it) {
        bool ok = false;
        const int a = it.key().toInt(&ok);
        if (!ok) continue;
        const QString name = it.value().toString().trimmed();
        if (!name.isEmpty()) nextNames[a] = name;
    }

    QVector<int> nextOrder;
    const QJsonArray order = ui.value("cardOrder").toArray();
    for (const QJsonValue& v : order) {
        if (!v.isDouble()) continue;
        const int a = v.toInt();
        if (!nextOrder.contains(a)) nextOrder.push_back(a);
    }

    QVector<StoredMapping> nextStored;
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
        for (const QJsonValue& x : o.value("servoIds").toArray())   m.servoIds.append(x.toInt(9));
        for (const QJsonValue& x : o.value("servoPwms").toArray())  m.servoPwms.append(x.toInt(1500));

        const int positions = _positionsCount(m.centers, m.thresholds);

        while (m.actions.size() < positions) m.actions << "No Action";
        if (m.actions.size() > positions)    m.actions = m.actions.mid(0, positions);

        while (m.repeats.size() < positions) m.repeats.push_back(false);
        if (m.repeats.size() > positions)    m.repeats = m.repeats.mid(0, positions);

        while (m.servoIds.size() < positions) m.servoIds.push_back(9);
        if (m.servoIds.size() > positions)    m.servoIds = m.servoIds.mid(0, positions);

        while (m.servoPwms.size() < positions) m.servoPwms.push_back(1500);
        if (m.servoPwms.size() > positions)    m.servoPwms = m.servoPwms.mid(0, positions);

        m.stableIndex = -999;
        m.pendingIndex = -999;
        m.pendingSinceMs = 0;
        m.lastFireMs = 0;
        m.lastRepeatMs = 0;

        if (m.axis < 0 || m.centers.isEmpty()) continue;

        int found = -1;
        for (int i = 0; i < nextStored.size(); ++i) {
            if (nextStored[i].axis == m.axis) { found = i; break; }
        }
        if (found >= 0) nextStored[found] = m;
        else            nextStored.push_back(m);
    }

    _axisNames = nextNames;
    _stored = nextStored;
    _cardOrderAxes = nextOrder;

    _normalizeCardOrder();
    _rebuildSummaries();
    _saveToSettings();

    emit mappingsChanged();
    _applyMappingToUiForAxis(_selectedAxis);
    emitActivePositionSnapshot();

    _updateRepeatTimerRunning();
    return QString();
}

QString AxisActionRouter::exportProfileToFile(const QUrl& fileUrl) const
{
    const QString chosenPath = _fileUrlToLocalPath(fileUrl);
    if (chosenPath.isEmpty()) return QStringLiteral("Invalid file path");

    const QFileInfo fi(chosenPath);
    QString fileName = fi.fileName();
    if (fileName.isEmpty()) {
        fileName = QStringLiteral("ActionProfile.json");
    }
    if (!fileName.endsWith(".json", Qt::CaseInsensitive)) {
        fileName += QStringLiteral(".json");
    }

    const QString dir = _actionConfigDirPath();
    const QString path = QDir(dir).filePath(fileName);

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return QStringLiteral("Cannot write file: %1").arg(f.errorString());
    }
    const QByteArray data = exportProfileJson().toUtf8();
    if (f.write(data) != data.size()) {
        return QStringLiteral("Write failed");
    }
    f.close();
    return QString();
}

QString AxisActionRouter::importProfileFromFile(const QUrl& fileUrl)
{
    const QString path = _fileUrlToLocalPath(fileUrl);
    if (path.isEmpty()) return QStringLiteral("Invalid file path");

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        return QStringLiteral("Cannot read file: %1").arg(f.errorString());
    }
    const QByteArray data = f.readAll();
    f.close();

    return importProfileJson(QString::fromUtf8(data));
}
