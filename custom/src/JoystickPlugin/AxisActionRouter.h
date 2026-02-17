#pragma once

#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>
#include <QtCore/QVector>
#include <QtCore/QPair>

class Vehicle;
class Joystick;

class AxisActionRouter : public QObject
{
    Q_OBJECT

            // Axis picker + live values
    Q_PROPERTY(QStringList axisList READ axisList NOTIFY axisListChanged)
    Q_PROPERTY(int selectedAxis READ selectedAxis WRITE setSelectedAxis NOTIFY selectedAxisChanged)
    Q_PROPERTY(int selectedAxisRaw READ selectedAxisRaw NOTIFY selectedAxisValueChanged)
    Q_PROPERTY(float selectedAxisNorm READ selectedAxisNorm NOTIFY selectedAxisValueChanged)

            // Auto follow axis ที่ขยับ
    Q_PROPERTY(bool autoSelectAxis READ autoSelectAxis WRITE setAutoSelectAxis NOTIFY autoSelectAxisChanged)

            // แกนที่มี mapping แล้ว
    Q_PROPERTY(QVariantList mappedAxes READ mappedAxes NOTIFY mappingsChanged)

            // Calibration / loaded mapping display
    Q_PROPERTY(bool calibrating READ calibrating NOTIFY calibratingChanged)
    Q_PROPERTY(int calibratedPositions READ calibratedPositions NOTIFY calibrationChanged)
    Q_PROPERTY(QVariantList calibratedCenters READ calibratedCenters NOTIFY calibrationChanged)
    Q_PROPERTY(QVariantList calibratedThresholds READ calibratedThresholds NOTIFY calibrationChanged)
    Q_PROPERTY(QString calibrationHint READ calibrationHint NOTIFY calibrationChanged)

            // Pending mapping + stored mapping summaries
    Q_PROPERTY(QStringList pendingActions READ pendingActions NOTIFY pendingActionsChanged)
    Q_PROPERTY(QStringList mappingSummaries READ mappingSummaries NOTIFY mappingsChanged)

   public:
    explicit AxisActionRouter(QObject* parent = nullptr);

    Q_INVOKABLE void setJoystick(QObject* joystickObj);
    Q_INVOKABLE void setVehicle(QObject* vehicleObj);

    QStringList axisList() const { return _axisList; }

    int  selectedAxis() const { return _selectedAxis; }
    void setSelectedAxis(int axis);

    int   selectedAxisRaw()  const { return _selectedAxisRaw; }
    float selectedAxisNorm() const { return _selectedAxisNorm; }

    bool autoSelectAxis() const { return _autoSelectAxis; }
    void setAutoSelectAxis(bool v);

    QVariantList mappedAxes() const;

    bool calibrating() const { return _calibrating; }

    int calibratedPositions() const;
    QVariantList calibratedCenters() const;
    QVariantList calibratedThresholds() const;
    QString calibrationHint() const { return _calHint; }

    QStringList pendingActions() const { return _pendingActions; }
    QStringList mappingSummaries() const { return _mappingSummaries; }

    Q_INVOKABLE void startCalibration();
    Q_INVOKABLE void stopCalibration();
    Q_INVOKABLE void clearCalibration();

    Q_INVOKABLE void setPendingAction(int posIndex, const QString& action);
    Q_INVOKABLE void commitSelectedAxisMapping();

            // ใช้ใน QML (การ์ด Remove)
    Q_INVOKABLE void removeMapping(int axis);
    Q_INVOKABLE void clearAllMappings();

   signals:
    void axisListChanged();
    void selectedAxisChanged();
    void selectedAxisValueChanged();

    void autoSelectAxisChanged();

    void calibratingChanged();
    void calibrationChanged();

    void pendingActionsChanged();
    void mappingsChanged();

    void requestTriggerQgcAction(const QString& actionTitle);

   private slots:
    void _onAxisValueChanged(int axis, int value);
    void _onRawButtonPressedChanged(int button, int pressed);

   private:
    struct StoredMapping {
        int axis = -1;
        QVector<float> centers;
        QVector<float> thresholds;
        QStringList actions;

                // anti-jitter stabilizer
        int    stableIndex    = -999;   // zone ที่ commit แล้ว
        int    pendingIndex   = -999;   // zone ที่กำลังรอ stable
        qint64 pendingSinceMs = 0;      // เริ่มรอเมื่อไหร่
        qint64 lastFireMs     = 0;      // กันยิงถี่
    };

    void _attach(Joystick* js);
    void _detach();
    void _rebuildAxisList();

    float _norm(int v) const;

    void _calibFeed(float v, qint64 nowMs);
    void _finalizeCalibrationFromSamples();

    void _triggerAction(const QString& label);
    void _arm(bool arm);
    void _emergencyStop();

    StoredMapping* _findMapping(int axis);
    void _applyMappingToUiForAxis(int axis);

    bool _tryTriggerViaJoystickActions(const QString& actionTitle);
    bool _trySetVehicleFlightMode(const QString& modeTitle);

    QObject* _assignableActionObjectAt(int idx) const;

    void _autoSelectAxisIfMoved(int axis, int raw, float norm, qint64 nowMs);

    Vehicle*  _vehicle = nullptr;
    Joystick* _js      = nullptr;

    QStringList _axisList;
    int   _selectedAxis = 0;
    int   _selectedAxisRaw = 0;
    float _selectedAxisNorm = 0.f;

    bool _autoSelectAxis = true;

    QVector<float> _lastAxisNorm;
    qint64 _lastAutoPickMs = 0;
    int    _lastAutoAxis   = -1;

    bool _calibrating = false;
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
    QString _makeJoystickKey(Joystick* js) const;
    void _loadFromSettings();
    void _saveToSettings() const;
    void _rebuildSummaries();
};
