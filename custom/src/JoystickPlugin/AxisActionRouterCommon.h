#pragma once

#include <QtCore/QtGlobal>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QVariant>
#include <QtCore/QMetaType>
#include <QtCore/QVector>
#include <QtCore/QObject>

#include <limits>

static inline bool _isNoAction(QString a)
{
    a = a.trimmed();
    return a.isEmpty()
           || a.compare("No Action", Qt::CaseInsensitive) == 0
           || a.compare("None",      Qt::CaseInsensitive) == 0;
}

static inline QString _normalizeStored(QString a)
{
    a = a.trimmed();
    return _isNoAction(a) ? QStringLiteral("No Action") : a;
}

static inline int _positionsCount(const QVector<float>& centers, const QVector<float>& thresholds)
{
    return thresholds.isEmpty() ? centers.size() : (thresholds.size() + 1);
}

static inline int _nearestCenterIndex(float v, const QVector<float>& centers)
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

static inline int _indexFromThresholds(float v, const QVector<float>& th)
{
    int idx = 0;
    while (idx < th.size() && v >= th[idx]) ++idx;
    return idx;
}

static inline QString _propStr(QObject* o, const char* name)
{
    if (!o) return QString();
    const QVariant v = o->property(name);
    if (!v.isValid()) return QString();
    const QString s = v.toString().trimmed();
    return s.isEmpty() ? QString() : s;
}

static inline QString _normalizeTitleKey(QString s)
{
    s = s.trimmed();
    s.remove('&');
    return s.toLower();
}

static inline QString _cleanActionText(QString s)
{
    s = s.trimmed();
    s.remove('&');
    return s.trimmed();
}

static inline QStringList _variantToStringList(const QVariant& v)
{
    if (!v.isValid()) return {};
    if (v.canConvert<QStringList>()) return v.toStringList();
    if (v.typeId() == QMetaType::QVariantList) {
        const QVariantList vl = v.toList();
        QStringList out; out.reserve(vl.size());
        for (const QVariant& it : vl) out << it.toString();
        return out;
    }
    return {};
}
