/**
 * Hint: اختبارات محرك الحضور والمعاينة والاعتماد والتقارير التاريخية
 * التواريخ المستخدمة: 2026-10-20 ثلاثاء (الملف النموذجي)، 21 أربعاء، 22 خميس، 25 أحد، 26 إثنين، 27 ثلاثاء
 */
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

let T;

before(async () => {
  await h.start();
  T = await h.adminToken();
  const imp = await h.upload('/employees/import-excel', h.MASTER_FILE, T);
  assert.equal(imp.status, 200);
});
after(h.stop);

function recordOf(data, employeeId) {
  return data.records.find(r => r.employeeId === employeeId || r.employee_id === employeeId);
}

test('sample file preview and commit by previewId', async () => {
  const prev = await h.upload('/attendance/preview', h.SAMPLE_DAY_FILE, T);
  assert.equal(prev.status, 200);
  const d = prev.body.data;
  assert.ok(d.previewId);
  assert.equal(d.days.length, 1);
  assert.equal(d.days[0].date, '2026-10-20');
  assert.equal(d.days[0].stats.total, 263);
  const c = await h.api('POST', '/attendance/commit', { previewId: d.previewId, date: '2026-10-20' }, T);
  assert.equal(c.status, 200);
});

test('commit rejects client-supplied punch lists and unknown previews', async () => {
  const emp = h.activeEmployee(0);
  let r = await h.api('POST', '/attendance/commit', {
    date: '2026-10-21',
    punchList: [{ empCode: emp.emp_code, firstPunch: '2026-10-21 07:00:00', lastPunch: '2026-10-21 20:00:00', punchCount: 2 }]
  }, T);
  assert.equal(r.status, 400);
  r = await h.api('POST', '/attendance/commit', { previewId: 'does-not-exist', date: '2026-10-21' }, T);
  assert.equal(r.status, 404);
  r = await h.api('POST', '/attendance/commit', { previewId: 'x', date: 'not-a-date' }, T);
  assert.equal(r.status, 400);
});

test('multi-day file is split into separate days', async () => {
  const emp = h.activeEmployee(1);
  const buf = h.makePunchFile([[emp.emp_code, '2026-10-25 09:00:00'], [emp.emp_code, '2026-10-26 16:00:00']]);
  const prev = await h.upload('/attendance/preview', buf, T, 'multi.xlsx');
  assert.equal(prev.status, 200);
  const days = prev.body.data.days;
  assert.deepEqual(days.map(d => d.date), ['2026-10-25', '2026-10-26']);
  for (const day of days) {
    const rec = recordOf(day, emp.id);
    assert.equal(rec.punchCount, 1);
  }
});

test('junk file gives a clean 400', async () => {
  const r = await h.upload('/attendance/preview', Buffer.from('not an excel file at all'), T, 'junk.xlsx');
  assert.equal(r.status, 400);
});

test('record year comes from the date, not the active year', async () => {
  const emp = h.activeEmployee(2);
  // 2025-12-31 أربعاء
  await h.previewAndCommit(T, h.makePunchFile([[emp.emp_code, '2025-12-31 09:30:00'], [emp.emp_code, '2025-12-31 15:10:00']]), '2025-12-31');
  const years = h.db.prepare("SELECT DISTINCT year FROM attendance_records WHERE date = '2025-12-31'").all();
  assert.deepEqual(years.map(y => y.year), [2025]);
});

test('hourly leave (10:00-11:00) excuses lateness inside the window only', async () => {
  const a = h.activeEmployee(3);
  const b = h.activeEmployee(4);
  let r = await h.api('POST', '/leaves', { employeeId: a.id, leaveType: 'زمنية (ساعية)', startDate: '2026-10-22', endDate: '2026-10-22', startTime: '10:00', endTime: '11:00' }, T);
  assert.equal(r.status, 201);
  r = await h.api('POST', '/leaves', { employeeId: b.id, leaveType: 'زمنية (ساعية)', startDate: '2026-10-22', endDate: '2026-10-22', startTime: '10:00', endTime: '11:00' }, T);
  assert.equal(r.status, 201);
  const data = await h.previewAndCommit(T, h.makePunchFile([
    [a.emp_code, '2026-10-22 10:50:00'], [a.emp_code, '2026-10-22 15:05:00'],
    [b.emp_code, '2026-10-22 11:20:00'], [b.emp_code, '2026-10-22 15:05:00']
  ]), '2026-10-22');
  const ra = recordOf(data, a.id);
  const rb = recordOf(data, b.id);
  assert.equal(ra.status, 'ON_TIME');
  assert.equal(ra.lateMinutes, 0);
  assert.equal(rb.status, 'LATE');
  assert.equal(rb.lateMinutes, 20);
});

test('hourly leave validation', async () => {
  const a = h.activeEmployee(3);
  let r = await h.api('POST', '/leaves', { employeeId: a.id, leaveType: 'زمنية (ساعية)', startDate: '2026-10-22', endDate: '2026-10-23', startTime: '10:00', endTime: '11:00' }, T);
  assert.equal(r.status, 400);
  r = await h.api('POST', '/leaves', { employeeId: a.id, leaveType: 'زمنية (ساعية)', startDate: '2026-10-22', endDate: '2026-10-22', startTime: '11:00', endTime: '10:00' }, T);
  assert.equal(r.status, 400);
  r = await h.api('POST', '/leaves', { employeeId: a.id, leaveType: 'اعتيادية', startDate: '2026-12-10', endDate: '2026-12-01' }, T);
  assert.equal(r.status, 400);
});

test('leave added after commit equals full recalculation', async () => {
  const late = h.db.prepare(`
    SELECT employee_id FROM attendance_records WHERE date = '2026-10-20' AND status IN ('LATE','VERY_LATE') LIMIT 1
  `).get();
  const r = await h.api('POST', '/leaves', { employeeId: late.employee_id, leaveType: 'اعتيادية', startDate: '2026-10-20', endDate: '2026-10-20' }, T);
  assert.equal(r.status, 201);
  const afterLeave = h.db.prepare("SELECT status FROM attendance_records WHERE employee_id = ? AND date = '2026-10-20'").get(late.employee_id).status;
  await h.api('POST', '/attendance/recalculate', { date: '2026-10-20' }, T);
  const afterRecalc = h.db.prepare("SELECT status FROM attendance_records WHERE employee_id = ? AND date = '2026-10-20'").get(late.employee_id).status;
  assert.equal(afterLeave, 'ON_LEAVE');
  assert.equal(afterRecalc, afterLeave);
});

test('recalculation keeps the rules snapshot unless asked to use current rules', async () => {
  const onTime = h.db.prepare("SELECT employee_id FROM attendance_records WHERE date='2026-10-20' AND status='ON_TIME' AND late_minutes=0 AND early_bonus_minutes=0 LIMIT 1").get();
  // تغيير وقت بداية الدوام إلى 08:00 يجعل الجميع متأخرين لو طُبق بأثر رجعي
  await h.api('PUT', '/settings', { work_start_time: '08:00', bonus_enabled: 'false' }, T);
  await h.api('POST', '/attendance/recalculate', { date: '2026-10-20' }, T);
  let st = h.db.prepare("SELECT status FROM attendance_records WHERE employee_id=? AND date='2026-10-20'").get(onTime.employee_id).status;
  assert.equal(st, 'ON_TIME');
  await h.api('POST', '/attendance/recalculate', { date: '2026-10-20', useCurrentRules: true }, T);
  st = h.db.prepare("SELECT status FROM attendance_records WHERE employee_id=? AND date='2026-10-20'").get(onTime.employee_id).status;
  assert.notEqual(st, 'ON_TIME');
  // إرجاع القواعد
  await h.api('PUT', '/settings', { work_start_time: '10:00', bonus_enabled: 'true' }, T);
  await h.api('POST', '/attendance/recalculate', { date: '2026-10-20', useCurrentRules: true }, T);
});

test('schedule workDays are validated and snapshotted from templates', async () => {
  const e = h.activeEmployee(5);
  let r = await h.api('POST', '/schedules/assign', { employeeIds: [e.id], scheduleType: 'FIXED', workDays: ['0', '1', '2', '3', '4'] }, T);
  assert.equal(r.status, 400);
  const tpl = h.db.prepare('SELECT id FROM schedule_templates ORDER BY id LIMIT 1').get();
  r = await h.api('POST', '/schedules/assign', { employeeIds: [e.id], scheduleType: 'FIXED', templateId: tpl.id }, T);
  assert.equal(r.status, 200);
  const row = h.db.prepare("SELECT work_days_json FROM employee_schedules WHERE employee_id=? AND schedule_type='FIXED'").get(e.id);
  assert.deepEqual(JSON.parse(row.work_days_json), [0, 1, 2, 3, 4]);
  // تعديل القالب لا يغير الجدول المعيّن مسبقاً
  await h.api('PUT', `/schedules/templates/${tpl.id}`, { workDays: [0] }, T);
  const data = await h.previewAndCommit(T, h.makePunchFile([[e.emp_code, '2026-10-27 09:50:00'], [e.emp_code, '2026-10-27 15:10:00']]), '2026-10-27');
  assert.equal(recordOf(data, e.id).status, 'ON_TIME');
  await h.api('PUT', `/schedules/templates/${tpl.id}`, { workDays: [0, 1, 2, 3, 4] }, T);
});

test('historical reports keep an employee who resigned later', async () => {
  const someone = h.db.prepare("SELECT employee_id FROM attendance_records WHERE date='2026-10-20' AND status='ON_TIME' LIMIT 1").get();
  await h.api('PUT', `/employees/${someone.employee_id}`, { status: 'استقالة' }, T);
  const monthly = await h.api('GET', '/reports/monthly?year=2026&month=10', undefined, T);
  assert.ok(monthly.body.data.report.some(x => x.employee_id === someone.employee_id));
  const daily = await h.api('GET', '/attendance/daily?date=2026-10-20', undefined, T);
  assert.ok(daily.body.data.records.some(x => x.employee_id === someone.employee_id));
});

test('deleting an employee is soft and preserves attendance history; restore works', async () => {
  const e = h.db.prepare("SELECT employee_id FROM attendance_records WHERE date='2026-10-20' LIMIT 1 OFFSET 7").get().employee_id;
  const before = h.db.prepare('SELECT COUNT(*) c FROM attendance_records WHERE employee_id=?').get(e).c;
  let r = await h.api('DELETE', `/employees/${e}`, undefined, T);
  assert.equal(r.status, 200);
  assert.equal(h.db.prepare('SELECT COUNT(*) c FROM attendance_records WHERE employee_id=?').get(e).c, before);
  const list = await h.api('GET', '/employees', undefined, T);
  assert.ok(!list.body.data.some(x => x.id === e));
  r = await h.api('POST', `/employees/${e}/restore`, undefined, T);
  assert.equal(r.status, 200);
});

test('department change through edit is recorded as a transfer', async () => {
  const e = h.activeEmployee(9);
  await h.api('PUT', `/employees/${e.id}`, { department: 'قسم جديد للاختبار' }, T);
  const t = h.db.prepare('SELECT COUNT(*) c FROM employee_transfers WHERE employee_id=?').get(e.id).c;
  assert.equal(t, 1);
});

test('monthly report validates input and has the extra columns', async () => {
  let r = await h.api('GET', '/reports/monthly?year=abc&month=99', undefined, T);
  assert.equal(r.status, 400);
  r = await h.api('GET', '/reports/monthly?year=2026&month=10', undefined, T);
  const row = r.body.data.report[0];
  for (const k of ['days_missed_punch', 'days_early_leave', 'days_holiday']) assert.ok(k in row, k);
});

test('generic export tolerates special characters in title', async () => {
  const r = await fetch(`${h.base}/reports/export-excel`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${T}` },
    body: JSON.stringify({ title: 'a/b:c[1]', fileName: 'تقرير', headers: ['x'], rows: [['1']] })
  });
  assert.equal(r.status, 200);
});

test('daily response exposes eligible employee count', async () => {
  const r = await h.api('GET', '/attendance/daily?date=2030-01-01', undefined, T);
  assert.ok(r.body.data.eligibleEmployees > 200);
});
