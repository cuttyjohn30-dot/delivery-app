-- ============================================================
-- 001_drivers_and_kpi.sql
-- เพิ่มตารางข้อมูลหลักของคนขับ (drivers) + View คำนวณ KPI รายคน
--
-- แนวคิด: ไม่แยกตาราง "1 คนขับ 1 ตาราง" แต่เก็บงานรวมใน deliveries/km_log
-- เหมือนเดิม แล้วผูกกับคนขับผ่านคอลัมน์ driver_name (คีย์ตัวพิมพ์เล็ก)
-- KPI คำนวณอัตโนมัติด้วย View — เพิ่มคนขับใหม่แค่ insert 1 แถวในตาราง drivers
-- ============================================================

-- ------------------------------------------------------------
-- 1) ตารางข้อมูลหลักของคนขับ
-- ------------------------------------------------------------
create table if not exists drivers (
  id             bigint generated always as identity primary key,
  name           text not null unique,              -- คีย์ที่ตรงกับ deliveries.driver_name (เช่น 'kia')
  display_name   text,                              -- ชื่อแสดงผลสวย ๆ (ถ้าไม่ใส่ใช้ name)
  team           text not null default 'Transport', -- ทีม/หน่วยงาน: Transport / BU / Outsource
  icon           text default '🧑',                 -- อีโมจิไอคอนในแอปคนขับ
  active         boolean not null default true,     -- false = ซ่อนจากหน้าเลือกคนขับ
  monthly_target integer,                            -- เป้า KPI: จำนวนงานต่อเดือน (ใช้เทียบ % บรรลุเป้า)
  created_at     timestamptz not null default now()
);

-- ย้ายรายชื่อคนขับที่เคยฮาร์ดโค้ดใน index.html มาไว้ในตาราง
insert into drivers (name, team, icon) values
  ('kia',  'Transport', '🧑'),
  ('Den',  'Transport', '👨'),
  ('Bom',  'Transport', '🧑'),
  ('Tong', 'Transport', '🧑')
on conflict (name) do nothing;

-- ------------------------------------------------------------
-- 2) KPI รวมทั้งหมด (all-time) ต่อคนขับ
-- ------------------------------------------------------------
create or replace view driver_kpi as
select
  d.name                                                                  as driver_name,
  coalesce(d.display_name, d.name)                                        as display_name,
  d.team,

  -- จำนวนงาน + % สำเร็จ
  count(dl.id)                                                            as total_jobs,
  count(dl.id) filter (where dl.status = 'done')                          as done_jobs,
  count(dl.id) filter (where dl.status is distinct from 'done')           as pending_jobs,
  round(
    100.0 * count(dl.id) filter (where dl.status = 'done')
    / nullif(count(dl.id), 0)
  , 1)                                                                    as done_pct,

  -- % ตรงเวลา: งานที่ done และเวลาส่งจริง (done_at, เวลาไทย) ไม่เกินเวลานัด (scheduled_time)
  count(dl.id) filter (
    where dl.status = 'done' and dl.scheduled_time is not null
  )                                                                       as scheduled_done_jobs,
  count(dl.id) filter (
    where dl.status = 'done' and dl.scheduled_time is not null
      and (dl.done_at at time zone 'Asia/Bangkok')::time <= dl.scheduled_time
  )                                                                       as ontime_jobs,
  round(
    100.0 * count(dl.id) filter (
      where dl.status = 'done' and dl.scheduled_time is not null
        and (dl.done_at at time zone 'Asia/Bangkok')::time <= dl.scheduled_time
    )
    / nullif(count(dl.id) filter (
      where dl.status = 'done' and dl.scheduled_time is not null
    ), 0)
  , 1)                                                                    as ontime_pct,

  -- ยอดเงินรวมของงานที่ส่งสำเร็จ
  coalesce(sum(dl.price) filter (where dl.status = 'done'), 0)            as revenue_done,

  -- ระยะทางรวม (กม.) จาก km_log
  coalesce((
    select sum(k.km_end - k.km_start)
    from km_log k
    where k.driver_name = d.name
      and k.km_start is not null and k.km_end is not null
  ), 0)                                                                   as total_km

from drivers d
left join deliveries dl on dl.driver_name = d.name
group by d.name, d.display_name, d.team;

-- ------------------------------------------------------------
-- 3) KPI รายเดือน ต่อคนขับ (ใช้ทำกราฟ/เทียบเป้ารายเดือน)
-- ------------------------------------------------------------
create or replace view driver_kpi_monthly as
with jobs as (
  select
    driver_name,
    to_char(date, 'YYYY-MM')                                             as month,
    count(*)                                                             as total_jobs,
    count(*) filter (where status = 'done')                             as done_jobs,
    count(*) filter (where status is distinct from 'done')              as pending_jobs,
    count(*) filter (
      where status = 'done' and scheduled_time is not null
    )                                                                    as scheduled_done_jobs,
    count(*) filter (
      where status = 'done' and scheduled_time is not null
        and (done_at at time zone 'Asia/Bangkok')::time <= scheduled_time
    )                                                                    as ontime_jobs,
    coalesce(sum(price) filter (where status = 'done'), 0)              as revenue_done
  from deliveries
  where driver_name is not null
  group by driver_name, to_char(date, 'YYYY-MM')
),
km as (
  select
    driver_name,
    to_char(date, 'YYYY-MM')                                             as month,
    coalesce(sum(km_end - km_start) filter (
      where km_start is not null and km_end is not null
    ), 0)                                                                as total_km
  from km_log
  where driver_name is not null
  group by driver_name, to_char(date, 'YYYY-MM')
)
select
  coalesce(j.driver_name, k.driver_name)                                 as driver_name,
  coalesce(j.month, k.month)                                             as month,
  coalesce(j.total_jobs, 0)                                              as total_jobs,
  coalesce(j.done_jobs, 0)                                               as done_jobs,
  coalesce(j.pending_jobs, 0)                                            as pending_jobs,
  round(100.0 * coalesce(j.done_jobs, 0) / nullif(j.total_jobs, 0), 1)   as done_pct,
  round(100.0 * j.ontime_jobs / nullif(j.scheduled_done_jobs, 0), 1)     as ontime_pct,
  coalesce(j.revenue_done, 0)                                            as revenue_done,
  coalesce(k.total_km, 0)                                                as total_km
from jobs j
full join km k on k.driver_name = j.driver_name and k.month = j.month;

-- ============================================================
-- หมายเหตุ
-- * View ใช้ deliveries.driver_name เป็นคีย์ (ยังไม่ผูก FK แข็ง เพื่อไม่ให้
--   แถวเก่าที่ driver_name = null พัง) หากต้องการความเข้มงวดขึ้นภายหลัง
--   ค่อยเพิ่ม driver_id + FK ทีหลังได้
-- * เวลา on-time คำนวณโดยแปลง done_at เป็นเวลาไทย (Asia/Bangkok) ก่อนเทียบ
--   กับ scheduled_time
-- ============================================================
