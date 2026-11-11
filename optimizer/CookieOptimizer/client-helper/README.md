# Cookie Slicer Helper — java agent ฝั่งผู้เล่น (ไม่บังคับ)

ตัวช่วยของม็อด **Cookie Slicer** ให้หน้าต่าง Slicer ในเกมเห็นสิ่งที่ Lua มองไม่เห็น + ปรับ RAM เกมแบบกดปุ่มเดียว
ไม่แก้ไฟล์เกมบนดิสก์ (ยกเว้น Setup กด 1 ซ่อม ProjectZomboid64.json แบบมี backup) · แก้คลาสเกมในหน่วยความจำแค่ 2 จุด
(shader 1.1.0, กล่องหน้าโหลด 1.2.0) ถ้าเกมอัปเดตแล้วหาจุดไม่เจอ = ปล่อยโค้ดเกมเดิม

## 1.2.0 (11 พ.ย.)

- **ประหยัด RAM ระดับ Java** (`run.ps1` / `run.sh`, ไม่แตะไฟล์เกม): `_JAVA_OPTIONS` = `-Xmx` จาก heap.txt +
  `-XX:+IgnoreUnrecognizedVMOptions -XX:+UseCompactObjectHeaders -XX:+UseStringDeduplication -XX:ZUncommitDelay=60 -XX:SoftMaxHeapSize=<4/5 ของ Xmx>m`
  (หัว object 12→8 byte, String ซ้ำเก็บชุดเดียว, ZGC พยายามอยู่ใต้ 4/5 (ไม่ต่ำกว่านี้: ถ้าข้อมูลจริงเกินเพดานนุ่ม ZGC จะเก็บกวาดถี่ = กิน CPU) และคืน RAM ที่ไม่ใช้ให้ Windows ใน 60 วิ; flag ที่ Java ไม่รู้จัก = ข้าม)
  ปิดได้จากหน้าต่าง (Version Slicer) → helper เขียน `ramsave.txt` (`ramsave=0`) มีผลตอนเปิดเกมครั้งหน้า
  เทสกับ JDK 25: ZGC + compact headers เปิดพร้อมกันได้ · LWJGL/JOML ใช้ Unsafe แบบคำนวณ offset (ไม่ hard-code) = ใช้กับ compact headers ได้
- **อะไรกิน RAM**: ปุ่มในหน้าต่าง → `HeapReport` เรียก DiagnosticCommand `gcClassHistogram` (เกมหยุด 1–3 วิ) → `Zomboid/Lua/CookieSlicer_heap.txt`
  (40 คลาสใหญ่สุด `c<i>=bytes|count|class` + 15 กลุ่ม package `g<i>=bytes|group`) → ให้ผู้เล่นส่งไฟล์มา แล้วค่อย patch ส่วนที่กินจริง
- ไฟล์ pc เพิ่ม: `heap_committed_mb` (ที่ Windows เห็น), `nonheap_mb`, `ramsave_now` / `ramsave_next`, `gc`, `heap_report` / `heap_report_t`,
  `json_file` / `json_xmx_mb` / `json_issue` (pzopt, aot, agent:<ชื่อ>, broken), `load_box`
- **เข้าเซิฟไม่ได้**: `ConsoleWatch` อ่าน `console.txt` ทุก 1 วิ (อ่านอย่างเดียว) จับ ram / pzopt / workshop / modmissing / map / files /
  version / banned / already / access / full / ping / net / luamod → `Zomboid/Lua/CookieSlicer_diag.txt` (ของรอบก่อน = `_diag_prev.txt`)
  · "ConnectToServerState: Start" = เริ่มรอบใหม่
- **กล่องวิธีแก้บนจอโหลด**: `LoadPatcher` ชี้ `Core.EndFrameUI()` 4 จุดใน `GameLoadingState.render` ไปที่ `LoadHook` → ขึ้นกล่อง
  เมื่อเกมขึ้น error / โดนเตะ / log มีปัญหาที่ทำให้เข้าไม่ได้ / โหลดเกิน 3 นาที · ข้อความจาก Translate ของม็อด (`UI_CookieSlicer_Fix_*`)
- **Setup กด 1** เช็ค + ซ่อม `ProjectZomboid64.json`: ลบของ PZ Optimization (classpath pzopt, AOTCache / SharedArchiveFile),
  -Xmx ที่เกิน RAM เครื่อง; backup `ProjectZomboid64.json.cookieslicer-backup` ครั้งแรกครั้งเดียว, รักษา tab/CRLF เดิม
  · กด 2 คืน backup เฉพาะถ้าแก้แค่ RAM (ถ้าเคยมี PZ Optimization ไม่คืน เพราะเกมจะพังอีก) · กด 3 บอกสถานะไฟล์

## ทำอะไร

ทุก 2 วิ เขียน `Zomboid\Lua\CookieSlicer_pc.txt`:

| ค่า | มาจาก |
|---|---|
| `cpu_total` / `cpu_game` | CPU ทั้งเครื่อง / ของเกม (%) — OperatingSystemMXBean |
| `main_thread` + `busiest_thread` | เธรดของเกมที่ใช้ CPU มากสุด (% ของ 1 คอร์) = ตัวที่ทำให้ FPS ตัน |
| `ram_total_mb` / `ram_free_mb` | RAM เครื่อง / RAM ว่าง |
| `heap_used_mb` / `heap_live_mb` / `heap_max_mb` | RAM เกมตอนนี้ / หลังเก็บกวาดครั้งล่าสุด / เพดาน (-Xmx) |
| `heap_recommend_mb` | ครึ่งหนึ่งของ RAM เครื่อง (4–16 GB, เหลือให้ Windows ≥ 4 GB) |
| `gc_ms_per_min` | เวลาที่เกมหยุดเก็บกวาด RAM ต่อนาที |

ผู้เล่นกดปุ่ม "ให้ RAM เกม N GB" ในหน้าต่าง → ม็อดเขียน `CookieSlicer_request.txt` → helper เขียน `heap.txt`
ข้าง jar (รับเฉพาะ 2 GB ถึง RAM เครื่อง − 2 GB, ไม่เกิน 32 GB) → ตอนเปิดเกมครั้งหน้า `run.ps1` ส่ง `_JAVA_OPTIONS=-Xmx…`
(เทส 10 พ.ย. เช้า: `_JAVA_OPTIONS` ชนะ -Xmx ใน json) **ไม่แก้ไฟล์เกมเลย**

## ทำไมต้องผ่าน Steam launch option (ไม่ใส่ -javaagent ใน ProjectZomboid64.json)

`ProjectZomboid64.exe` โหลด jvm.dll เอง ไม่ผ่าน java.exe → `instrument.dll` (ตัวโหลด agent) หา `jli.dll` ไม่เจอ
→ JVM ไม่ขึ้น = เกมเปิดไม่ได้ (launch test 10 พ.ย. T1: "Can't find dependent libraries"; T2: ใส่ `jre64\bin` หน้า PATH แล้วผ่าน)
→ `run.ps1` ตั้ง PATH + `JAVA_TOOL_OPTIONS=-javaagent` ให้เฉพาะ process เกม แล้วเปิด exe เดิมที่ Steam ส่งมา (`%command%`)
ใช้ Java ของเกมเวอร์ชันปัจจุบันเสมอ (Steam อัปเดตเกมแล้วยังใช้ได้) · ไม่มี jar = เกมเปิดแบบปกติ

## ติดตั้ง / อัปเดต / ถอด (สำหรับผู้เล่น)

1. เข้าเซิฟ Cookie Cheetah สักครั้ง (Steam โหลดม็อด Cookie Slicer ที่มี `helper\CookieSlicerHelper.jar` + `run.ps1`) แล้วปิดเกม
2. ดับเบิลคลิก `CookieSlicer-Setup.bat` (แจกทาง Discord) → กด `1`
3. ครั้งแรกครั้งเดียว: Steam > Project Zomboid > Properties > Launch Options → Ctrl+A, Ctrl+V (setup ก๊อปให้แล้ว
   อ่าน launch options เดิมจาก Steam มาต่อท้ายให้ด้วย เช่น `-cachedir=...`) → เปิดเกม
- อัปเดต helper = รัน Setup กด 1 อีกที (ไม่ต้องแก้ Steam ซ้ำ) · ไม่อัปเดตเอง: helper มีสิทธิ์เต็มในเครื่อง จึงให้ผู้เล่นกดเอง
- ถอด = กด 2: ลบ jar + heap.txt + ไฟล์ใน Zomboid\Lua, ก๊อป launch options เดิมให้วางกลับ (`run.ps1` ยังอยู่ → ถ้ายังไม่แก้ Steam เกมก็ยังเปิดได้)
- เช็ค = กด 3: มีไฟล์ไหม, Steam launch option ตั้งแล้วไหม, RAM ที่เลือกไว้
- Linux: `bash cookieslicer-setup.sh` (เขียน run.sh เอง, บอก launch option `bash ".../run.sh" %command%`)
- .bat/.sh อัปขึ้น Workshop ไม่ได้ (เกมห้าม .bat .sh .exe .dll .so .zip) → แจกทาง Discord · .jar/.ps1 อยู่ในม็อดได้
- Windows อาจเตือนไฟล์จากเน็ต: More info → Run anyway

## Build / test

```
PZ_COMPILE_JAR=... sh build.sh      # JDK 21+, คอมไพล์กับสำเนา projectzomboid.jar (ดู build.sh)
PZ_JAR=... JAVA25=... CONSOLE_TXT=... sh test/run.sh
#   HelperTest, JoinTest (log -> ปัญหา, ไฟล์ diag, json, patch หน้าโหลดกับคลาสเกมจริง), RamTest (histogram, สวิตช์, ไฟล์ pc), ShaderTest
```
ทดสอบ 11 พ.ย. (1.2.0): Java ผ่านหมด (JoinTest กับ console.txt จริงของ Pie = ไม่มีปัญหาค้าง, RamTest ทั้งมี/ไม่มี flag)
· run.ps1 ใน pwsh 7 + JVM 25 จริง: flag ครบ, ramsave=0 ปิดได้, heap ผิดช่วง = ไม่ใส่ -Xmx · json ของ Setup เทส 5 ชุดใน pwsh 7
(สะอาด = ไม่แตะ, 16 GB บนเครื่อง 16 GB → 8 GB, PZ Optimization → ลบ + uninstall ไม่คืน, ไฟล์เสีย, agent อื่น) · UI Lua เทสใน lupa (TH/EN)
ยังไม่ได้ลองกับเกมจริง
ทดสอบ 10 พ.ย.: เทส Java ผ่านหมด · โหลดเป็น `-javaagent` บน JDK 25 ได้ (เขียนไฟล์ทุก 2 วิ, ไม่ใช่เกม = ไม่ทำอะไร)
· run.ps1 / run.sh เทสกับ JVM 25: agent โหลดได้ (path มีช่องว่าง), -Xmx จาก heap.txt, argument เดิมครบ, ไม่มี jar = เปิดปกติ
· Setup.bat (ส่วน PowerShell) เทสใน pwsh 7 กับ Steam ปลอม: อ่าน launch options เดิม (มี \" และ \\) ต่อท้ายถูก, อัปเดตไม่ถามซ้ำ, ถอดแล้วคืนค่าเดิม · .sh เทสกับ Steam ปลอม
ยังไม่ได้ลองกับเกมจริง (ต้องให้ Pie ลอง)
