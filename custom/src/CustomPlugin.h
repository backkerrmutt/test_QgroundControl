#pragma once

#include <QtCore/QLoggingCategory>
#include <QtCore/QVariantList>

#include "QGCCorePlugin.h"
#include "QGCOptions.h"
#include "QGCLoggingCategory.h"

class FactMetaData;
class QQmlApplicationEngine;

// forward declare พอ
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
    Q_PROPERTY(QObject* axisActionRouter READ axisActionRouter CONSTANT)

   public:
    explicit CustomPlugin(QObject* parent = nullptr);
    ~CustomPlugin() override;

    static QGCCorePlugin* instance();
    static void registerQmlTypes();

            // QML จะอ่านผ่าน: QGroundControl.corePlugin.axisActionRouter
    QObject* axisActionRouter() const;

            // เผื่อ C++ ใช้ (ไม่ expose ให้ QML โดยตรง)
    AxisActionRouter* axisActionRouterTyped() const { return _axisActionRouter; }

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

    AxisActionRouter* _axisActionRouter = nullptr;
};
