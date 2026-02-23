#pragma once

#include <QtCore/QLoggingCategory>
#include <QtCore/QPointer>
#include <QtCore/QVariantList>

#include "QGCCorePlugin.h"
#include "QGCOptions.h"
#include "QGCLoggingCategory.h"

class FactMetaData;
class QQmlApplicationEngine;

// [Joystick Module] Forward declare is enough in header (keep compile time low).
// The concrete type is included in CustomPlugin.cc where we create/register it.
class AxisActionRouter;

Q_DECLARE_LOGGING_CATEGORY(CustomLog)

//-----------------------------------------------------------------------------

class CustomOptions;
class CustomPlugin;

class CustomFlyViewOptions : public QGCFlyViewOptions
{
   public:
    explicit CustomFlyViewOptions(CustomOptions* options, QObject* parent = nullptr);

    bool showInstrumentPanel(void) const final;
    bool showMultiVehicleList(void) const final;
};

//-----------------------------------------------------------------------------

class CustomOptions : public QGCOptions
{
   public:
    explicit CustomOptions(CustomPlugin* plugin, QObject* parent = nullptr);

    bool wifiReliableForCalibration(void) const final;
    bool showFirmwareUpgrade(void) const final;
    QGCFlyViewOptions* flyViewOptions(void) const final;

   private:
    CustomPlugin*         _plugin         = nullptr;
    CustomFlyViewOptions* _flyViewOptions = nullptr;
};

//-----------------------------------------------------------------------------

class CustomPlugin : public QGCCorePlugin
{
    Q_OBJECT

            // =====================================================================
            // [Joystick Module] QML bridge entry point (MOST IMPORTANT)
            //
            // This exposes the AxisActionRouter instance to QML as:
            //   QGroundControl.corePlugin.axisActionRouter
            //
            // Your JoystickConfig.qml / JoystickConfigButtons.qml bind to this.
            // =====================================================================
    Q_PROPERTY(QObject* axisActionRouter READ axisActionRouter CONSTANT)

   public:
    explicit CustomPlugin(QObject* parent = nullptr);
    ~CustomPlugin() override;

            // [custom-example pattern] Plugin singleton used by QGCCorePlugin::instance()
    static QGCCorePlugin* instance();

            // =====================================================================
            // [Joystick Module] QML type registration hook
            //
            // Registers:
            //  - CustomJoystickConfigController (creatable from QML)
            //  - AxisActionRouter (uncreatable, exposed by the plugin)
            //
            // QML side uses:
            //   import QGroundControl.Controllers 1.0
            // =====================================================================
    static void registerQmlTypes();

            // =====================================================================
            // [Joystick Module] Router accessor for QML
            //
            // QML reads this property via the Q_PROPERTY above.
            // Keep return type as QObject* for QML friendliness.
            // =====================================================================
    QObject* axisActionRouter() const;

            // [Joystick Module] Optional typed accessor for C++ (NOT exposed to QML)
    AxisActionRouter* axisActionRouterTyped() const { return _axisActionRouter; }

            // ---- QGCCorePlugin overrides (same as custom-example) ----
    QGCOptions*            options(void) final;
    QString                brandImageIndoor(void) const final;
    QString                brandImageOutdoor(void) const final;
    bool                   overrideSettingsGroupVisibility(const QString& name) final;
    bool                   adjustSettingMetaData(const QString& settingsGroup, FactMetaData& metaData) final;
    void                   paletteOverride(const QString& colorName, QGCPalette::PaletteColorInfo_t& colorInfo) final;
    QQmlApplicationEngine* createQmlApplicationEngine(QObject* parent) final;

   private slots:
    void _advancedChanged(bool advanced);

   private:
    void _addSettingsEntry(const QString& title, const char* qmlFile, const char* iconFile = nullptr);

    CustomOptions* _options = nullptr;
    QVariantList   _customSettingsList;

            // =====================================================================
            // [Joystick Module] Owned router instance (lifetime = CustomPlugin lifetime)
            //
            // Created in CustomPlugin.cc constructor:
            //   _axisActionRouter = new AxisActionRouter(this);
            // Parent is 'this' so it will auto-delete with the plugin.
            // =====================================================================
    AxisActionRouter* _axisActionRouter = nullptr;
};
