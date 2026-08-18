-- ============================================================
-- 002_kia_schedule.sql
-- แยกตารางงานของ kia (ที่เพิ่มจากปฏิทิน) ออกเป็นตารางเดี่ยว
--
-- เหตุผล: เดิมงานที่ kia เพิ่มเองในปฏิทินถูกเก็บปนใน deliveries
-- แล้วโดนขั้นตอนล้างข้อมูลของการอัปโหลด Excel ลบทิ้งซ้ำ ๆ
-- การแยกตารางทำให้การอัปโหลด (ซึ่งแตะเฉพาะ deliveries)
-- ไม่มีทางลบตารางงานของ kia ได้อีกเลยในทุกกรณี
--
-- ★ ส่วนที่ 1 ถูก apply กับฐานข้อมูลจริงแล้ว (2026-08-18
--   ผ่าน Supabase migration ชื่อ create_kia_schedule)
-- ============================================================

-- ---------- ส่วนที่ 1: สร้างตาราง (apply แล้ว) ----------
create table if not exists kia_schedule (
  id             bigint generated always as identity primary key,
  date           date not null,
  customer       text not null,
  job_type       text,
  notes          text,
  status         text not null default 'pending',
  scheduled_time time,
  request_by     text,
  arrived_at     timestamptz,
  done_at        timestamptz,
  created_at     timestamptz not null default now()
);

alter table kia_schedule enable row level security;

create policy "allow all kia_schedule" on kia_schedule
  for all to anon, authenticated
  using (true) with check (true);

-- ---------- ส่วนที่ 2: ย้ายงานค้างเดิมเข้าตารางใหม่ ----------
-- ★ ให้รันส่วนนี้ "หลัง" deploy โค้ดใหม่ขึ้น production แล้วเท่านั้น
--   (ถ้ารันก่อน งานจะหายจากปฏิทินชั่วคราว เพราะโค้ดเก่าอ่านแต่ deliveries)
--
-- insert into kia_schedule (date, customer, job_type, notes, status, scheduled_time, request_by, arrived_at, done_at)
-- select date, customer, job_type, notes, status, scheduled_time, request_by, arrived_at, done_at
-- from deliveries
-- where driver_name = 'kia' and added_by = 'driver' and status = 'pending';
--
-- delete from deliveries
-- where driver_name = 'kia' and added_by = 'driver' and status = 'pending';
