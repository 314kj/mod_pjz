# Launch test บนเครื่อง host — 10 พ.ย. 2026 (B42.22.2 rev 3d39148846, Zulu JRE 25.0.5)

เครื่องมือ: `tools/cookie-launch-test.ps1` + `cookie-agent-test.jar` (agent ทดสอบ เขียนรายงานอย่างเดียว ไม่แตะเกม) · รัน `ProjectZomboid64.exe` ตรงจาก PowerShell โดยตั้ง env เฉพาะ process เกม ไม่แก้ JSON

## สรุป
- **agent**: `JAVA_TOOL_OPTIONS=-javaagent:...` + `jre64\bin` หน้า PATH ของ process ลูก → ใช้ได้ ไม่ต้องทำ native shim
- **heap**: `_JAVA_OPTIONS=-Xmx...` ชนะ JSON → ไม่ต้องแก้ JSON
- **GC**: `_JAVA_OPTIONS=-XX:-UseZGC -XX:+UseG1GC` → G1 ทำงาน (`-XX:+UseZGC` exe ใส่เอง ไม่ได้มาจาก JSON; ใส่ `+UseG1GC` อย่างเดียว VM ไม่ขึ้น)
- **เข้าเซิฟพร้อม agent**: ผ่าน (role=user, เล่น ~12.5 นาที, ออกปกติ, ไม่โดน kick) เมื่อส่ง `-cachedir=P:\Zomboid` ด้วย
- launcher ต้องเปิดผ่าน Steam `"launcher.exe" %command%` เพื่อพา launch options เดิม (เช่น `-cachedir`) ไปด้วย

## ผล
| test | ตั้งค่า | ผล |
|---|---|---|
| T1 | `JAVA_TOOL_OPTIONS=-Xmx5000m -javaagent:...` PATH เดิม | JVM ไม่ขึ้น: "Could not find agent library instrument on the library path, with error: Can't find dependent libraries" (ออกทาง stdout) |
| T2 | T1 + `jre64\bin` หน้า PATH | agent โหลดได้ · heap 16384 MB → `-Xmx16g` ของ JSON ชนะ `-Xmx` ใน JAVA_TOOL_OPTIONS |
| T3 | agent + `_JAVA_OPTIONS=-Xmx5000m` | heap 5000 MB |
| T4 | agent + `_JAVA_OPTIONS=-XX:-UseZGC -XX:+UseG1GC` | G1 · heap 16384 · G1 ใช้ compressed oops ได้ (ZGC ไม่ได้) |
| T5 join #1 | agent, ไม่มี `-cachedir` | kick `Anti-cheat="ChecksumUpdate" reason="Script incorrect checksum"` |
| T5 join #2 | agent + `-cachedir=P:\Zomboid` | fully connected (loading 35.5 s) · ออกปกติ · ไม่มี kick |

## Kick ตอน join #1 = bug ของเกมเรื่อง junction ไม่ใช่ agent
- `ScriptManager.Load` ใช้ path canonical ของโฟลเดอร์ม็อดเป็น base แต่ไฟล์ที่ไล่หาใช้ path ผ่าน junction (`C:\Users\<user>\Zomboid` → `P:\Zomboid`) → relativize ไม่ได้ → `getAbsolutePath` คืน null → `NetChecksum$Checksummer.addFile` NPE → ไฟล์หายจาก checksum ฝั่ง client → เซิฟ kick
- เกิดเฉพาะม็อดที่โหลดจาก `Zomboid\Workshop` (local) เมื่อ cache dir เป็น junction · เกิดก่อนมี agent ด้วย
- แก้: ส่ง `-cachedir=P:\Zomboid` เสมอ · เป็น bug vanilla 42.22.2 ที่รายงาน TIS ได้

## IntegrityReport (`zombie.core.IntegrityReport`, ใหม่ใน 42.22)
- ตรวจลายเซ็น jar, ไฟล์ .class เกินบน classpath, และ `-javaagent/-agentpath/-agentlib` → ต่อท้าย `Core.getVersion()` เช่น `classpath=1,agents=1`
- ไม่เจอการส่งค่านี้ไปเซิฟใน packet ของ client แต่ Lua อ่านได้ผ่าน `getCore():getVersion()`
- **ห้ามแตะ/ซ่อน** · `_JAVA_OPTIONS` (heap/GC/JFR) ไม่ถูกนับ
- `classpath=1` บนเครื่อง host มาจากไฟล์ค้าง `ProjectZomboid\zombie\IsoChunkMap.class` (override เก่า วางผิดที่ ไม่เคยถูกโหลด) → ย้ายออกได้

## Anti-cheat ระหว่างเล่น
- `HitShortDistance` (VehicleHitZombiePacket, action=Log) ตอนขับรถชนซอมบี้ · ผู้เล่นที่ไม่มี agent ก็โดน check อื่น (`HitWeapon`, `Speed`) → ปกติของ 42.22 แต่จับตาต่อ
