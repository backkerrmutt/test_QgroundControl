# QGC v5.0.0 — Custom Joystick “Axis → Virtual Buttons” (How to Port & Use)

เอกสารนี้อธิบายแบบ “ทำตามได้เลย” สำหรับการย้าย (port) และใช้งานฟีเจอร์ **AxisActionRouter** + UI “Axis → Virtual Buttons” ไปยัง QGroundControl **v5.0.0** อีกโปรเจกต์หนึ่ง โดยยึดแนวทาง `custom-example` (ไม่แก้ core)

---

## 0) คุณจะได้อะไรจากโมดูลนี้

- Calibrate แกน/สวิตช์ให้เป็น 1–3 ตำแหน่ง (center/threshold)
- แมปแต่ละตำแหน่งให้เป็น Action (Arm/Disarm/E-Stop/QGC Actions/Flight Modes)
- Trigger แบบ stable (กันสั่น/กันเด้ง)
- เรียงลำดับการ์ดแกนได้ (Drag reorder)
- Export/Import โปรไฟล์เป็น JSON / ไฟล์ `.json`
- เซฟค่าตาม joystick (ผ่าน `QSettings`)

---

## 1) โครงสร้างไฟล์ที่ต้องมี (ปลายทาง)

ให้แน่ใจว่าใน repo QGC v5.0.0 ปลายทาง มีโฟลเดอร์ `custom/` ตามแนว `custom-example` แล้วไฟล์ต่อไปนี้อยู่ครบ

### 1.1 C++ (logic + controller)
- `custom/src/CustomPlugin.h`
- `custom/src/CustomPlugin.cc`
- `custom/src/JoystickPlugin/AxisActionRouter.h`
- `custom/src/JoystickPlugin/AxisActionRouter.cc`
- `custom/src/JoystickPlugin/CustomJoystickConfigController.h`
- `custom/src/JoystickPlugin/CustomJoystickConfigController.cc`

### 1.2 QML override (UI)
- `custom/qml/UI/VehicleSetup/JoystickConfig.qml`
- `custom/qml/UI/VehicleSetup/JoystickConfigButtons.qml`

### 1.3 Build/Resource (สำคัญมาก)
- `custom/CMakeLists.txt`
- `custom/custom.qrc`

> ถ้าขาด `custom.qrc` หรือ path ใน qrc ไม่ตรง จะเจอ error แนว `qrc_custom.cpp ... missing ... .qml`

---

## 2) ขั้นตอนการ Port (ทำตามลำดับ)

### Step 1 — เตรียม repo ปลายทาง
1. checkout QGC **tag v5.0.0**
2. ตรวจว่ามีโฟลเดอร์ `custom-example/` ใน repo (ของ official)
3. สร้างโฟลเดอร์ `custom/` จาก `custom-example/` (ถ้ายังไม่มี)
   - วิธีง่าย: copy ทั้งโฟลเดอร์ `custom-example/` → วางเป็น `custom/`

### Step 2 — คัดลอกไฟล์ custom joystick ของคุณไปทับ
จากโปรเจกต์ต้นทาง ให้คัดลอกไฟล์ตามข้อ 1 ไปทับในปลายทาง โดยคง path เดิมให้ตรง

### Step 3 — ตรวจ `custom/custom.qrc` ให้ path ตรงจริง
เปิด `custom/custom.qrc` แล้วเช็คว่า “อ้างไฟล์ที่มีอยู่จริง” เช่น
- `qml/UI/VehicleSetup/JoystickConfig.qml`
- `qml/UI/VehicleSetup/JoystickConfigButtons.qml`

**กฎเหล็ก:** ชื่อไฟล์ / ตัวพิมพ์เล็กใหญ่ / โฟลเดอร์ ต้องตรง 100%

### Step 4 — ตรวจ `custom/CMakeLists.txt` ว่า compile ไฟล์ C++ ของคุณ
ใน `custom/CMakeLists.txt` ต้องมีการเพิ่ม source อย่างน้อย
- `src/CustomPlugin.cc`
- `src/JoystickPlugin/AxisActionRouter.cc`
- `src/JoystickPlugin/CustomJoystickConfigController.cc`
และผูก resource:
- `custom.qrc`

> ถ้า build ผ่านแต่ UI ไม่มา ส่วนใหญ่คือ QML ไม่ถูก pack เข้า qrc หรือ override ไม่ถูกโหลด

### Step 5 — Clean & Reconfigure แล้ว Build
แนะนำทำตามนี้เพื่อล้าง cache qrc เก่า:
1. ลบ/clean โฟลเดอร์ build
2. CMake configure ใหม่
3. build target ของ custom (เช่น `Custom-QGroundControl`)

---

## 3) จุดเชื่อม (Integration Points) ที่ต้องทำงาน

### 3.1 ฝั่ง C++: `CustomPlugin` ต้อง expose router ให้ QML
ใน `CustomPlugin.h`
- ต้องมี `Q_PROPERTY(QObject* axisActionRouter READ axisActionRouter CONSTANT)`

ใน `CustomPlugin.cc`
- ต้องสร้าง instance:
  - `_axisActionRouter = new AxisActionRouter(this);`
- ต้องคืนค่าให้ QML:
  - `QObject* CustomPlugin::axisActionRouter() const { return static_cast<QObject*>(_axisActionRouter); }`
- ต้อง register QML types:
  - `qmlRegisterType<CustomJoystickConfigController>(...)`
  - `qmlRegisterUncreatableType<AxisActionRouter>(...)`

### 3.2 ฝั่ง QML: ต้องผูก joystick/vehicle เข้ากับ router
ใน `JoystickConfig.qml` ต้องมี logic แบบนี้ (แนวคิด):
- `controller.axisActionRouter.setJoystick(joystickManager.activeJoystick)`
- `controller.axisActionRouter.setVehicle(globals.activeVehicle)`

ถ้าไม่ set 2 ตัวนี้:
- router จะไม่มี raw axis feed
- และไม่สามารถสั่ง flight mode / arm ได้ (เพราะไม่มี vehicle)

---

## 4) วิธีใช้งานใน UI (Runtime)

ไปที่:
**Application Settings → Joystick → Button Assignment**

คุณจะเห็น 2 ส่วนหลัก:

### A) Calibrate Axis
1. เลือก **Axis** ที่เป็นสวิตช์/แกนที่ต้องการ
2. ตั้ง `Use positions:` = 1 / 2 / 3
3. กด **Start Calibrate**
4. ขยับสวิตช์ไปแต่ละตำแหน่ง แล้ว “ค้างนิ่งสั้น ๆ” ให้ระบบจับค่า
5. กด **Stop (Save)**

หลัง save จะเห็น:
- Detected positions
- Centers
- Thresholds

### B) Axis → Virtual Buttons
1. แต่ละการ์ดคือ “แกนที่ calibrate แล้ว”
2. แต่ละ `Pos 0 / Pos 1 / Pos 2` เลือก action ได้จาก dropdown
3. ทดสอบขยับสวิตช์จริง → action จะ trigger เมื่ออยู่ตำแหน่งนิ่ง

#### Reorder Cards
1. กด **Edit**
2. ลาก handle `⋮⋮` เพื่อย้ายการ์ด
3. กด **Done**

#### Remove Mapping
- กด **Remove** บนการ์ดนั้นเพื่อเอา mapping ออก

---

## 5) Export / Import โปรไฟล์

ในกล่อง “Axis → Virtual Buttons” มีปุ่ม:

- **View JSON**: แสดง JSON ในหน้าต่าง (copy ได้)
- **Export File**: บันทึกเป็น `.json`
- **Import File**: นำเข้า `.json`

> ใช้กรณี:
> - ย้ายเครื่อง
> - ย้ายโปรเจกต์
> - ทำโปรไฟล์หลายชุด

---

## 6) เช็คลิสต์ Debug (เจอบ่อยสุด)

### (1) Build error: qrc missing .qml
- เปิด `custom/custom.qrc` แล้วเช็ค path ว่าถูกจริง
- Clean build folder แล้ว build ใหม่

### (2) QML error: `CustomJoystickConfigController is not a type`
- เช็ค `CustomPlugin::registerQmlTypes()` ว่า register แล้ว
- เช็ค QML ว่า import ถูก:
  - `import QGroundControl.Controllers 1.0`

### (3) UI โผล่ แต่ axisRouter เป็น null / ใช้งานไม่ได้
- เช็คว่า build เป็น “custom build” จริง (ไม่ใช่ QGC core ปกติ)
- เช็ค `CustomPlugin` ถูกใช้เป็น corePlugin
- เช็ค `JoystickConfig.qml` เรียก `setJoystick` และ `setVehicle` แล้ว

### (4) เลือก Flight Mode แล้วไม่เปลี่ยน
- ต้องมี `globals.activeVehicle` จริง
- ชื่อโหมดต้องตรงกับ `veh->flightModes()` (case/spacing)

---

## 7) Note สำคัญเรื่องเวอร์ชัน
เอกสารนี้อ้างอิง QGC **v5.0.0** (tag เดียวกัน)
ถ้าขยับไปเวอร์ชันอื่น อาจต้องปรับ:
- properties ของ Joystick/QML component names
- โครงสร้าง QML override
- method names ใน controller/model

---

## 8) Quick Summary 
- ย้าย `custom/` ให้ครบ (C++ + QML + qrc + CMake)
- `CustomPlugin` ต้อง:
  - registerQmlTypes()
  - new AxisActionRouter(this)
  - expose Q_PROPERTY axisActionRouter
- `JoystickConfig.qml` ต้อง:
  - setJoystick(activeJoystick)
  - setVehicle(activeVehicle)
- Clean + Reconfigure + Build ใหม่ทุกครั้งที่แก้ qrc/QML

---
End.