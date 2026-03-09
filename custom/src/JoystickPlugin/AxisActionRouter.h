#pragma once

#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>
#include <QtCore/QVector>
#include <QtCore/QPair>
#include <QtCore/QHash>
#include <QtCore/QPointer>
#include <QtCore/QUrl>
#include <QtCore/QTimer>
#include <QtCore/QLoggingCategory>
#include "Joystick.h"


class QAction;
class Vehicle;
class Joystick;

Q_DECLARE_LOGGING_CATEGORY(AxisActLog)

class AxisActionRouter : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QStringList axisList READ axisList NOTIFY axisListChanged)
    Q_PROPERTY(int selectedAxis READ selectedAxis WRITE setSelectedAxis NOTIFY selectedAxisChanged)
    Q_PROPERTY(int selectedAxisRaw READ selectedAxisRaw NOTIFY selectedAxisValueChanged)
    Q_PROPERTY(float selectedAxisNorm READ selectedAxisNorm NOTIFY selectedAxisValueChanged)

    Q_PROPERTY(bool autoSelectAxis READ autoSelectAxis WRITE setAutoSelectAxis NOTIFY autoSelectAxisChanged)

    Q_PROPERTY(QVariantList mappedAxes READ mappedAxes NOTIFY mappingsChanged)

    Q_PROPERTY(bool calibrating READ calibrating NOTIFY calibratingChanged)
    Q_PROPERTY(int desiredPositions READ desiredPositions WRITE setDesiredPositions NOTIFY desiredPositionsChanged)
    Q_PROPERTY(int calibratedPositions READ calibratedPositions NOTIFY calibrationChanged)
    Q_PROPERTY(QVariantList calibratedCenters READ calibratedCenters NOTIFY calibrationChanged)
    Q_PROPERTY(QVariantList calibratedThresholds READ calibratedThresholds NOTIFY calibrationChanged)
    Q_PROPERTY(QString calibrationHint READ calibrationHint NOTIFY calibrationChanged)

    Q_PROPERTY(QStringList mappingSummaries READ mappingSummaries NOTIFY mappingsChanged)

   public:
    explicit AxisActionRouter(QObject* parent = nullptr);

    Q_INVOKABLE void setJoystick(QObject* joystickObj);
    Q_INVOKABLE void setVehicle(QObject* vehicleObj);

    Q_INVOKABLE int positionsForAxis(int axis) const;
    Q_INVOKABLE QStringList actionsForAxis(int axis) const;
    Q_INVOKABLE void setActionForAxis(int axis, int posIndex, const QString& action);

    Q_INVOKABLE int activePosForAxis(int axis) const;
    Q_INVOKABLE void emitActivePositionSnapshot();

    Q_INVOKABLE QString axisLabel(int axis) const;
    Q_INVOKABLE void setAxisLabel(int axis, const QString& label);
    Q_INVOKABLE void clearAxisLabel(int axis);

    Q_INVOKABLE QVariantList cardOrder() const;
    Q_INVOKABLE void setCardOrder(const QVariantList& order);

            // Profile export/import
    Q_INVOKABLE QString exportProfileJson() const;
    Q_INVOKABLE QString importProfileJson(const QString& jsonText);

    Q_INVOKABLE QString exportProfileToFile(const QUrl& fileUrl) const;
    Q_INVOKABLE QString importProfileFromFile(const QUrl& fileUrl);

            // Directory under Documents/<AppName>/ActionConfig (auto-created)
    Q_INVOKABLE QUrl actionConfigDirUrl() const;

    QStringList axisList() const { return _axisList; }

    int  selectedAxis() const { return _selectedAxis; }
    void setSelectedAxis(int axis);

    int   selectedAxisRaw()  const { return _selectedAxisRaw; }
    float selectedAxisNorm() const { return _selectedAxisNorm; }

    bool autoSelectAxis() const { return _autoSelectAxis; }
    void setAutoSelectAxis(bool v);

    QVariantList mappedAxes() const;

    bool calibrating() const { return _calibrating; }

    int desiredPositions() const { return _desiredPositions; }
    void setDesiredPositions(int v);

    int calibratedPositions() const;
    QVariantList calibratedCenters() const;
    QVariantList calibratedThresholds() const;
    QString calibrationHint() const { return _calHint; }

    QStringList mappingSummaries() const { return _mappingSummaries; }

    mutable QHash<QString, QPointer<QAction>> _appActionCache;

    Q_INVOKABLE void startCalibration();
    Q_INVOKABLE void stopCalibration();
    Q_INVOKABLE void clearCalibration();

    Q_INVOKABLE void removeMapping(int axis);
    Q_INVOKABLE void clearAllMappings();

    Q_INVOKABLE bool repeatForAxis(int axis, int posIndex) const;
    Q_INVOKABLE void setRepeatForAxis(int axis, int posIndex, bool enabled);

            // -----------------------------------------------------
            // API สำหรับดึง/บันทึกค่า Servo ID และ PWM จาก QML
            // -----------------------------------------------------
    Q_INVOKABLE int servoIdForAxis(int axis, int posIndex) const;
    Q_INVOKABLE void setServoIdForAxis(int axis, int posIndex, int id);

    Q_INVOKABLE int servoPwmForAxis(int axis, int posIndex) const;
    Q_INVOKABLE void setServoPwmForAxis(int axis, int posIndex, int pwm);

   signals:
    void axisListChanged();
    void selectedAxisChanged();
    void selectedAxisValueChanged();

    void autoSelectAxisChanged();

    void calibratingChanged();
    void desiredPositionsChanged();
    void calibrationChanged();

    void mappingsChanged();

            // Signal เฉพาะสำหรับ servo params (ID/PWM) เปลี่ยน
            // แยกออกมาเพื่อไม่ให้ QML recompute actionCombo.currentIndex
    void servoParamsChanged(int axis, int posIndex);

    void requestTriggerQgcAction(const QString& actionTitle);
    void axisActivePosChanged(int axis, int pos);

   private slots:
    void _onAxisValueChanged(int axis, int value);
    void _onRepeatTick();

   private:
    struct StoredMapping {
        int axis = -1;
        QVector<float> centers;
        QVector<float> thresholds;
        QStringList actions;

        int    stableIndex    = -999;
        int    pendingIndex   = -999;
        qint64 pendingSinceMs = 0;
        qint64 lastFireMs     = 0;
        QVector<bool> repeats;
        qint64 lastRepeatMs = 0;

        QVector<int> servoIds;
        QVector<int> servoPwms;
    };

    void _attach(Joystick* js);
    void _detach();
    void _rebuildAxisList();

    float _norm(int v) const;

    void _calibFeed(float v, qint64 nowMs);
    void _finalizeCalibrationFromSamples();

    void _triggerAction(const QString& label, int servoId = 0, int servoPwm = 0);

    void _arm(bool arm);
    void _emergencyStop();
    void _setServo(int id, int pwm);
    void _setActuator(int index, int rawValue);

    StoredMapping* _findMapping(int axis);
    void _applyMappingToUiForAxis(int axis);

    bool _tryTriggerViaJoystickActions(const QString& actionTitle);
    bool _trySetVehicleFlightMode(const QString& modeTitle);

    QObject* _assignableActionObjectAt(int idx) const;

    void _autoSelectAxisIfMoved(int axis, int raw, float norm, qint64 nowMs);

    void _loadFromSettings();
    void _saveToSettings() const;
    void _rebuildSummaries();

    QString _makeJoystickKey(Joystick* js) const;

    QVariantList _mappedAxesOrdered() const;
    void _normalizeCardOrder();

    static QString _fileUrlToLocalPath(const QUrl& url);

   private:
    QPointer<Vehicle> _vehicle;
    QPointer<Joystick> _js;

    QStringList _axisList;
    int   _selectedAxis     = 0;
    int   _selectedAxisRaw  = 0;
    float _selectedAxisNorm = 0.f;

    bool _autoSelectAxis = true;

    QVector<float> _lastAxisNorm;
    qint64 _lastAutoPickMs = 0;
    int    _lastAutoAxis   = -1;

    bool _calibrating = false;
    int _desiredPositions = 3;

    QVector<QPair<qint64, float>> _win;
    QVector<float> _stableSamples;

    QVector<float> _calCenters;
    QVector<float> _calThresholds;
    QString _calHint;

    qint64 _lastStableCommitMs = 0;
    float  _lastStableCommitV  = 999.f;

    QStringList _pendingActions;

    QVector<StoredMapping> _stored;
    QStringList _mappingSummaries;

    QString _jsKey;

    QHash<int, QString> _axisNames;
    QVector<int>        _cardOrderAxes;
    QTimer _repeatTimer;
    int    _repeatIntervalMs = 150;

   private:
    void _updateRepeatTimerRunning();
    bool _actionTitleCanRepeat(const QString& actionTitle) const;
    bool _isVehicleFlightModeTitle(const QString& modeTitle) const;

    bool     _tryTriggerViaAppActions(const QString& actionTitle) const;
    QAction* _findAppQActionByTitle(const QString& actionTitle) const;
};
