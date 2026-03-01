#pragma once

#include <QtCore/QLoggingCategory>
#include <QtCore/QPointer>
#include <QtCore/QVariantList>

#include "QGCCorePlugin.h"
#include "QGCOptions.h"
#include "QGCLoggingCategory.h"

class FactMetaData;
class QQmlApplicationEngine;

//-----------------------------------------------------------------------------
// CustomPlugin Implementation
//-----------------------------------------------------------------------------

// Forward declaration for the Joystick Handler (Delegation Pattern)
class CustomJoystickHandler;

//-----------------------------------------------------------------------------
// CustomPlugin Implementation
//-----------------------------------------------------------------------------

Q_DECLARE_LOGGING_CATEGORY(CustomLog)

//-----------------------------------------------------------------------------
// CustomFlyViewOptions
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
// CustomOptions
//-----------------------------------------------------------------------------
class CustomOptions : public QGCOptions
{
   public:
    explicit CustomOptions(CustomPlugin* plugin, QObject* parent = nullptr);

    bool wifiReliableForCalibration(void) const final;
    bool showFirmwareUpgrade(void) const final;
    QGCFlyViewOptions* flyViewOptions(void) const final;

   private:
    CustomPlugin* _plugin         = nullptr;
    CustomFlyViewOptions* _flyViewOptions = nullptr;
};

//-----------------------------------------------------------------------------
// CustomPlugin (Main Core Plugin)
//-----------------------------------------------------------------------------
class CustomPlugin : public QGCCorePlugin
{
    Q_OBJECT

            // Expose the AxisActionRouter to QML via the delegate handler
    Q_PROPERTY(QObject* axisActionRouter READ axisActionRouter CONSTANT)

   public:
    explicit CustomPlugin(QObject* parent = nullptr);
    ~CustomPlugin() override;

    static QGCCorePlugin* instance();

    //-----------------------------------------------------------------------------
    // CustomPlugin Implementation
    //-----------------------------------------------------------------------------

    static void registerQmlTypes();

            // Getter for the QML property
    QObject* axisActionRouter() const;

    //-----------------------------------------------------------------------------
    // CustomPlugin Implementation
    //-----------------------------------------------------------------------------


            // ---- QGCCorePlugin Overrides ----
    QGCOptions* options(void) final;
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

    //-----------------------------------------------------------------------------
    // CustomPlugin Implementation
    //-----------------------------------------------------------------------------

            // Delegate handler for joystick and axis routing operations
    CustomJoystickHandler* _joyHandler = nullptr;

    //-----------------------------------------------------------------------------
    // CustomPlugin Implementation
    //-----------------------------------------------------------------------------

};
