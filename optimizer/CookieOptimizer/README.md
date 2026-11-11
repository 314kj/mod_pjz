# Cookie Optimizer

ตัวจูน client + server ของเซิฟ CookieCheetah (Project Zomboid B42, dedicated) — ของเราเอง ไม่ใช่ dependency ของม็อดอื่น

> โฟลเดอร์นี้คือโค้ดฝั่งพัฒนา (ตัวช่วยผู้เล่น, ฝั่งเซิฟ, เครื่องมือเทส) วิธีลงสำหรับผู้เล่น / เหตุผลที่ไม่เหมาะเอาไปใช้ที่อื่น / ลิขสิทธิ์ ดูที่ [optimizer/README.md](../README.md)

## หลักที่ใช้ทั้ง repo

- ไม่ก๊อปโค้ดใคร: PZ Optimization ไม่มี LICENSE → ใช้ได้แค่ข้อเท็จจริง/ไอเดีย · ZombieBuddy / ZBBetterFPS / ZBLuaPerfMon เป็น MIT → ถ้าวันไหนเอาโค้ดมาใช้ ต้องใส่ credit + license ของเขา (ตอนนี้ยังไม่มี)
- ห้ามแตะหรือซ่อน `zombie.core.IntegrityReport` (ในคลาสเขียนไว้ว่าจะแบน workshop) ให้ `agents=` / `classpath=` แสดงตามจริง
- สคริปต์ทุกตัวไม่ start/stop เซิฟ ไม่รีสตาร์ทเครื่อง ไม่แก้ไฟล์ในโฟลเดอร์เกมหรือ `ProjectZomboid64.json` — ตั้งค่าผ่าน environment ของ process เกมเท่านั้น
- ไฟล์ที่ build ได้ (`.jar`) และผลเทส (`.jfr`, csv) ไม่ขึ้น git

## โครงสร้าง

ม็อด Workshop ของ Cookie Slicer (หน้าต่างในเกม, โทนภาพ, คิวงานโหลดพื้นที่) อยู่ที่ [`optimizer/CookieSlicer`](../CookieSlicer)

```
tools/
  cookie-gc-ab.ps1          วัด ZGC vs G1 บนเครื่อง client จริง (ใช้ตอนนี้)
  cookie-launch-test.ps1    เทสว่า env / agent / heap / GC ส่งเข้าเกมได้ไหม (ทำเสร็จแล้ว 10 พ.ย.)
  agent-test/               java agent ทดสอบ (เขียนรายงานอย่างเดียว) + build.ps1
server-agent/               Cookie Slicer: java agent ของเซิฟ กระจายงาน Lua ตอนโหลด cell ไปหลาย tick (ดู README ในโฟลเดอร์)
client-helper/              Cookie Slicer Helper: java agent ฝั่งผู้เล่น (ไม่บังคับ) วัด CPU/RAM + RAM เกมกดปุ่มเดียว, setup/ = ตัวติดตั้งแจกทาง Discord
docs/
  launch-test-2026-11-10.md ผล launch test
```

## cookie-gc-ab.ps1 — A/B ZGC vs G1

เปิดเกม 1 ครั้งต่อ 1 รอบ ต่างกันแค่ GC (heap เท่ากันทุกรอบ) แล้วเก็บ:
- RAM ของเกม (working set, private working set = ตัวเลขใน Task Manager, private bytes), RAM ว่างของเครื่อง
- CPU % ของเกม, GPU memory / GPU 3D % ของเกม (ตัวนับของ Windows)
- Java Flight Recorder: GC pause (รวม / สูงสุด / p99 / จำนวนครั้งที่เกิน 1 เฟรม), ZGC allocation stall, heap หลัง GC
- (ไม่บังคับ) frame time จริงด้วย PresentMon ของ Intel (MIT) ถ้าใส่ `-PresentMon <path ของ exe>` — จะถาม UAC ตอนเริ่มแต่ละรอบ

คำสั่ง (PowerShell ธรรมดา ไม่ต้อง admin, เปิด Steam ไว้, ปิดเกมก่อน):

```powershell
cd F:\github_mod\optimizer\CookieOptimizer\tools
powershell -ExecutionPolicy Bypass -File .\cookie-gc-ab.ps1 -CacheDir P:\Zomboid -HeapMB 8192
```

- `-CacheDir P:\Zomboid` ต้องใส่ทุกครั้ง (เหมือน launch option ใน Steam — ไม่ใส่จะโดน kick เรื่อง checksum ของ 42.22.2)
- `-HeapMB 8192` = heap ที่จะแนะนำผู้เล่นทั่วไป (ไม่ใส่ = ใช้ `-Xmx` ใน JSON)
- `-Order ZGC,G1,G1,ZGC` ถ้าอยากได้ 4 รอบ (สลับลำดับกันผลจาก cache ของดิสก์)
- `-PlayMinutes 15` เวลาเล่นต่อรอบ (มีเสียงบี๊บเตือน)

แต่ละรอบ: กด Enter → เกมเปิด → เข้าเซิฟ → เล่นเส้นทาง/ฉากเดิมทุกรอบ ~15 นาที → Quit to desktop → สคริปต์เปิดรอบต่อไปเอง

ผลอยู่ที่ `P:\Zomboid\Logs\cookie-ab\<วันที่-เวลา>\` (`ab-summary.txt` อ่านง่าย, `ab-summary.csv`, `samples-*.csv`, `*.jfr`)
สรุปใหม่จากโฟลเดอร์เดิมได้: `.\cookie-gc-ab.ps1 -AnalyzeDir <โฟลเดอร์>`

ตัวเลขทั้งหมดคิดเฉพาะช่วงเล่น (หลัง join 30 วิ ถึงก่อนออก 10 วิ) — เวลา join อ่านจาก `*_connections.txt` ของเซิฟในโฟลเดอร์ Logs

## ลำดับงาน

1. A/B ZGC vs G1 (ตอนนี้)
2. Launcher v1 ไม่มี agent: ตั้ง heap/GC ผ่าน `_JAVA_OPTIONS`, เช็คเครื่องก่อนเข้าเซิฟ, คำแนะนำภาษาไทย, เปิดผ่าน Steam `"launcher.exe" %command%`
3. Build บน GitHub Actions + เซ็นไฟล์ (ไม่ build บนเครื่องใคร)
4. ฝั่ง Lua / เซิฟ: หา `collectgarbage()` ใน modlist, แก้ม็อดที่วน per-square / per-zombie

## License

© AKA / Cookie Cheetah สงวนลิขสิทธิ์ (all rights reserved) รายละเอียดที่ [optimizer/README.md](../README.md#ลิขสิทธิ์)
