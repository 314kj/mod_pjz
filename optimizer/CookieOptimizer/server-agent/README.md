# Cookie Slicer — java agent ฝั่งเซิฟ (dedicated เท่านั้น)

แก้อาการ **แมพดำ / ซอมบี้-รถโผล่ช้าตอนขับรถ** ที่ต้นเหตุ: ตอนเซิฟโหลด cell ใหม่ (64×64 ช่อง) เกมยิง Lua event
`LoadGridsquare` ให้ทุกช่องของ cell ใน tick เดียว ม็อดที่ฟัง event นี้รวมกัน ~76 µs ต่อช่อง → 1 cell หลายร้อย ms,
หลาย cell พร้อมกันหลายวินาที (JFR 10 พ.ย.: ขับ 5 นาที tick ค้าง ≥1 วิ 74 ครั้ง นานสุด 5.4 วิ) ระหว่างนั้นเซิฟไม่ส่งอะไรเลย

ผู้เล่นไม่ต้องลงอะไร ไม่ใช่ม็อด ไม่ขึ้น Workshop

## ทำอะไร

เปลี่ยนแค่ "เวลา" ที่ 3 คำสั่ง Lua นี้ทำงานตอน cell โหลด (ต่อ chunk 8×8):

1. `LoadGridsquare` ของทุกช่องที่มีของ
2. `SGlobalObjects.chunkLoaded` (ระบบ global object ของ Lua)
3. `LoadChunk`

แทนที่จะรันทันที จะจดไว้ต่อ chunk แล้วรันทีหลัง **ลำดับในแต่ละ chunk เหมือนเดิม** (ช่องทั้งหมด → global objects → LoadChunk):

- หลังจบแต่ละ tick ภายในงบเวลา (ให้ทั้ง tick ไม่เกิน ~80 ms, 5–60 ms ต่อ tick, งานค้างเยอะ = งบมากขึ้น) **chunk ที่ใกล้ผู้เล่นที่สุดก่อน**
- ทันที ถ้าผู้เล่นกำลังจะดาวน์โหลด chunk นั้น (ได้ chunk แบบเดียวกับที่เกมเคยส่ง) ไม่เกิน 25 ms ต่อ tick
- cell ที่ถูก unload (ไม่มีผู้เล่นอยู่ใกล้แล้ว) → งานที่ยังค้างของ cell นั้น **ทิ้ง** (v2, Pie OK 10 พ.ย.) โหลดครั้งหน้าม็อดก็ทำใหม่เอง
  (v1 รันให้ครบก่อน unload → tick ค้างได้ ~1.7 วิ; `unload=run` ในตั้งค่าเอาแบบเดิมกลับมาได้)
- v3: ตอนที่เกมเคยยิง LoadGridsquare / LoadChunk จะยิง `OnCookieSquareNow` / `OnCookieChunkNow` แทน ให้ handler ที่ต้องทำงานก่อนเกมปล่อยซอมบี้ลงห้อง
  (CSP ย้าย AliveJeem base zombie safety ไปไว้ตรงนั้น แล้วข้ามตอน event ช้ามาถึง) ไม่มี handler = แค่ lookup ครั้งเดียว
- เซฟโลกไม่รอคิว (งานที่ค้างรันต่อหลังเซฟ เซฟรอบหน้าก็ได้ครบ; `run_before_save=true` ให้รันก่อนเซฟ)
- ช่อง/chunk ที่หายจากโลกไปก่อนถึงคิว → ข้าม (โหลดครั้งหน้าก็ยิงใหม่ตามปกติ)

ส่วนอื่นของการโหลด chunk (ซอมบี้ รถ ของในตู้ erosion pathfinding collision) ไม่แตะ ยังทำใน tick เดิม

**ผลข้างเคียงที่ต้องรู้:** งานของม็อดตอนช่องโหลด (A-Life จดของ, Outposts ปิดการทุบลังในฐาน, KC ฯลฯ) อาจช้าไป
ไม่กี่ tick ถึงประมาณ 1–3 วิ ตอนขับเร็ว (ใกล้ผู้เล่นได้ก่อน) แทนที่เซิฟจะค้างทั้งเซิฟรอมัน

## v5: ถอด entity ออกจากรายการแบบเร็ว (11 พ.ย.)

JFR 11 พ.ย. 21:18–21:23 (ขับรถในเมืองใหม่): **cell unload = 20% ของเธรดหลัก** และ 98% ของเวลานั้นคือเกมไล่หา entity
ในรายการทีละตัวตั้งแต่ต้น (`Array.removeValue` ใน `EntityBucket.updateMembership` 63% + `EngineEntityManager.removeEntityInternal` 35%)
— แมพใหม่มี entity (ของคราฟต์ หญ้า NB ฯลฯ) หลายหมื่นตัว และทุก chunk ที่ unload ต้องถอดของตัวเองออกทีละตัว

- รายการพวกนี้ **ไม่เรียงลำดับ** (เกมสร้างด้วย `ordered=false`): ตอนลบ เกมเอาตัวท้ายมาใส่ช่องที่ลบ
- v5 จด "entity → ตำแหน่ง" ไว้ข้างๆ ทุกรายการ (อัปเดตทุกครั้งที่เพิ่ม/ลบ) ตอนลบหาตำแหน่งได้ทันที แล้วลบด้วย `removeIndex`
  ของเกมเอง → **รายการออกมาเหมือนเกมทำเองทุกตัว ทุกลำดับ**
- ก่อนใช้ตำแหน่งเช็คว่า entity อยู่ตรงนั้นจริง ไม่ตรง = ใช้การไล่หาของเกม แล้วสร้างสมุดจดใหม่ · เปลี่ยนจากเธรดอื่น / entity
  ซ้ำในรายการ / รายการแบบเรียงลำดับ = ใช้วิธีของเกม · error = กลับเป็นวิธีของเกมทั้ง session
- ตามสวิตช์เดิม (`!offslice` / bat / revision ไม่ตรง = วิธีของเกม) · ปิดเฉพาะส่วนนี้: `fast_entity_remove=false` ใน CookieSlicer.properties
- แก้เพิ่ม 4 จุดใน 2 คลาส (`EntityBucket.updateMembership`: add + removeValue, `EngineEntityManager.addEntityInternal` / `removeEntityInternal`)
- แลก: RAM ไม่กี่ MB (สมุดจด) + hash 1 ครั้งต่อการเพิ่ม · log ต่อนาทีมี `entity lists: removed N fast, M the game's own way, ...`
- เทส: EntityTest (200,000 คำสั่งสุ่ม เทียบรายการทุกขั้น กับ Array ตัวจริงของเกม, ลบ 60,000 ตัว: ไล่หา ~200 ms → ~6 ms),
  RealEntityTest (EntityBucket ตัวจริงของเกมที่ patch แล้ว vs ไม่ patch: ผลเหมือนกันทุกขั้น; คลาสผ่าน bytecode verifier ของ JDK 25)

## ปลอดภัยยังไง

- แก้แค่ "ปลายทางของการเรียก method" 14 จุดใน 7 คลาส (v5) ขนาดเท่าเดิม (ไม่มีโค้ดเกมอยู่ในนี้ ไม่แก้ jar ของเกม แก้ในหน่วยความจำตอนโหลดคลาส)
- ทุกจุดต้องเจอครบตามจำนวน ไม่งั้นคลาสนั้นไม่ถูกแก้เลย + log บอก; game revision ต้องเป็น `3d39148846` (42.22.2) ไม่งั้นทำงานแบบเกมเดิม
- error ในโค้ดเรา → ปิดตัวเอง รันงานที่ค้างทั้งหมด แล้วกลับเป็นแบบเกมเดิม
- `IntegrityReport` ไม่แตะ: log เซิฟจะขึ้น `version=42.22.2 3d39148846 agents=1` ตามจริง — การ join ใช้ `getVersionNumber()` ที่ไม่มีส่วนนี้ ผู้เล่นเข้าได้ปกติ
- ไม่ start/stop เซิฟ ไม่แตะไฟล์อื่น

## ติดตั้ง (Pie ทำเอง ตอนเซิฟปิด)

1. วาง `CookieSlicer.jar` ไว้ที่ `P:\cookiev1\cookie\CookieSlicer.jar`
2. `P:\cookiev1\StartServer64.bat` ใส่ `-javaagent:cookie\CookieSlicer.jar` หน้า `-cp`
3. (ครั้งเดียว) ใส่บรรทัดนี้ใน bat **ก่อน**บรรทัด java เพื่อให้เวอร์ชันใหม่ถูกสลับเข้าเองตอนเปิดเซิฟ:
   `if exist cookie\CookieSlicer.next.jar move /y cookie\CookieSlicer.next.jar cookie\CookieSlicer.jar >nul`
   ตอนเซิฟรันอยู่ห้ามเขียนทับ `CookieSlicer.jar` (JVM เปิดไฟล์ไว้) → ของใหม่วางเป็น `CookieSlicer.next.jar` แทน
4. เปิดเซิฟตามปกติ → console มี `[CookieSlicer] v5 loaded`, `patched ...` 7 บรรทัด, `ready (game revision 3d39148846): ON ...` (หรือ `OFF` ถ้า mode = off)

ถอด: ลบ `-javaagent:...` ออกจาก bat แล้วรีสตาร์ท

## ปิด/เปิดระหว่างเซิฟรัน (ไม่ต้องรีสตาร์ท)

ง่ายสุด (ไม่เปิด/ปิดเซิฟ แค่เขียนไฟล์สวิตช์):

| ทำที่ | เปิด | ปิด | ดูสถานะ |
|---|---|---|---|
| เครื่องเซิฟ: ดับเบิลคลิกใน `P:\cookiev1\cookie\` (ไฟล์อยู่ใน `tools/`) | `slicer-on.bat` | `slicer-off.bat` | `slicer-status.bat` |
| ในเกม พิมพ์ในแชต (แอดมินเท่านั้น, ต้อง v4 + CookieWatch ที่มี `CookieWatch_Slicer*.lua`) | `!onslice` | `!offslice` | `!slice` |

- bat เขียน `cookie\CookieSlicer.mode` · คำสั่งในเกมเขียน `Zomboid\Lua\CookieSlicer_mode.txt` (Lua เขียนนอกโฟลเดอร์นั้นไม่ได้) → **ไฟล์ที่ถูกแก้ล่าสุดชนะ** (v4)
- ไฟล์เปล่า `CookieSlicer.off` ข้าง jar = off เสมอ (ทับทุกอย่าง)
- คนที่ไม่ใช่แอดมิน (role ไม่มีสิทธิ์ ChangeAndReloadServerOptions) พิมพ์ `!offslice` = ขึ้นเป็นแชตธรรมดา ไม่มีผล
- v4 เขียน `CookieSlicer_status.txt` (ข้าง jar + `Zomboid\Lua`): ON/OFF ตั้งแต่กี่โมง ใครสั่ง + ตัวเลขนาทีล่าสุด — bat กับ `!slice` อ่านอันนี้

เช็คทุก 5 วิ: เปลี่ยนเป็น off → งานที่ค้างรันหมดทันที แล้วกลับเป็นแบบเกมเดิม / เปลี่ยนเป็น on → กลับมาทำงาน
ทั้งสองแบบ log ยังนับ tick + จำนวนผู้เล่น + จำนวน chunk ที่โหลด ให้เทียบกันได้ (A/B กับผู้เล่นจริงโดยไม่ต้องรีสตาร์ท)

## Log

`P:\cookiev1\cookie\CookieSlicer.log` (+ console) ทุก 60 วิ เช่น

```
60 s: players 12, chunks loaded 3100; ticks 598 (over 100 ms: 3, 1 s or more: 0, longest 140 ms); squares waited 41210, ran 40877 (in tick budget 39001,
before download 1876, before unload 0, before save 0), skipped (no longer loaded) 120 of which dropped with their cell 120; waiting now 333 squares in 4 chunks
(most 9120 in 96); longest square work in a tick 60 ms; chunk wait avg 310 ms, max 2400 ms
```

ตัวที่ดู: `1 s or more` (เดิม ~15 ต่อนาทีตอนขับ), `longest`, `chunk wait` (งานม็อดช้าไปเท่าไหร่)

ผลจริงบนเซิฟ 10 พ.ย. (v1, 6–7 คนออน): แบบเดิม 19:11–19:14 = 330–470 tick/นาที, ค้าง ≥1 วิ 8–17 ครั้ง/นาที, นานสุด 4.3 วิ ·
เปิด v1 19:15–19:19 = 553–584 tick/นาที, ค้าง ≥1 วิ 0–1, นานสุด 0.7–1.7 วิ (ตัวที่ ≥1 วิ มาจากรันงานค้างก่อน unload → v2 ทิ้งแทน),
chunk wait เฉลี่ย 1.3–4.9 วิ สูงสุด 31 วิ, Lua error 0 · Pie: แมพไม่ดำเลย

## ตั้งค่า (ไม่ต้องมีก็ได้)

ก๊อป `CookieSlicer.properties.example` เป็น `CookieSlicer.properties` ข้าง jar แล้วแก้ — v2 อ่านใหม่เองภายใน 5 วิ ไม่ต้องรีสตาร์ท (ยกเว้น `enabled`, `revision`)

## เช็คกับเกมเวอร์ชันใหม่ก่อนเปิดเซิฟ

```
P:\cookiev1\jre64\bin\java.exe -jar P:\cookiev1\cookie\CookieSlicer.jar check P:\cookiev1\java\projectzomboid.jar
```

ต้องขึ้น `ok` 5 บรรทัด (ถ้าเกมอัปเดต แม้ ok ทั้งหมด ตัว agent ก็จะไม่ทำงานจนกว่าจะแก้ `revision=` หรือออกเวอร์ชันใหม่)

## Build / test (ใน container ของ Claude หรือเครื่องที่มี JDK 21+)

```
sh build.sh        # stubs/ = ชื่อ+signature ของคลาสเกมที่เรียก (เอาไว้ compile เท่านั้น ไม่อยู่ใน jar)
sh test/run.sh     # เทสพฤติกรรมกับโลกปลอม (test/stubs) 10 กรณี
```

เทสกับ jar จริง 42.22.2 บน Java 25 (10 พ.ย.): `check` เจอครบ 10 จุด, คลาสที่แก้ผ่าน verifier ของ JVM 25 ทั้ง 5 คลาส
(และ patch ที่ตั้งใจให้ผิดโดน verifier จับได้ = การเช็คนี้เชื่อได้), เทสพฤติกรรมผ่านหมด: งาน Lua 1.75 วิ จาก 6 cell
→ กระจาย 29 tick ไม่มี tick เกิน 60 ms
