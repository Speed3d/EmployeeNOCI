/**
 * Hint: اختبارات الأمان والجلسات والصلاحيات
 */
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

let T;

before(async () => {
  await h.start();
  T = await h.adminToken();
});
after(h.stop);

test('fresh admin must change temporary password before using the API', async () => {
  // تم التغيير في adminToken؛ نتحقق أن مستخدماً جديداً بكلمة مؤقتة يُمنع
  await h.api('POST', '/settings/users', { username: 'tmpuser', password: 'Temp1234x', fullName: 'مؤقت', role: 'DATA_ENTRY' }, T);
  const tmp = await h.login('tmpuser', 'Temp1234x');
  assert.equal(tmp.user.mustChangePassword, true);
  const r = await h.api('GET', '/employees', undefined, tmp.token);
  assert.equal(r.status, 403);
  assert.equal(r.body.code, 'PASSWORD_CHANGE_REQUIRED');
});

test('login with non-string username returns 400, not 500', async () => {
  const r = await h.api('POST', '/auth/login', { username: 123, password: 'x' });
  assert.equal(r.status, 400);
});

test('malformed JSON returns 400 without leaking internals', async () => {
  const r = await h.api('POST', '/auth/login', '{bad json');
  assert.equal(r.status, 400);
  assert.equal(r.body.error, undefined);
});

test('rate limit cannot be bypassed with spoofed forwarding headers', async () => {
  await h.api('POST', '/settings/users', { username: 'victim', password: 'Victim123x', fullName: 'ضحية', role: 'DATA_ENTRY' }, T);
  let blocked = 0;
  for (let i = 0; i < 20; i++) {
    const r = await h.api('POST', '/auth/login', { username: 'victim', password: 'wrong' + i }, null, {
      'X-Forwarded-For': `1.1.1.${i}`,
      'CF-Connecting-IP': `2.2.2.${i}`
    });
    if (r.status === 429) blocked++;
  }
  assert.ok(blocked > 0, 'expected at least one 429');
});

test('invalid token returns 401 with SESSION_EXPIRED code', async () => {
  const r = await h.api('GET', '/employees', undefined, 'garbage.token.here');
  assert.equal(r.status, 401);
  assert.equal(r.body.code, 'SESSION_EXPIRED');
});

test('token in query string is not accepted', async () => {
  const res = await fetch(`${h.base}/employees?token=${T}`);
  assert.equal(res.status, 401);
});

test('old token is revoked after password change', async () => {
  await h.api('POST', '/settings/users', { username: 'de1', password: 'Data1234x', fullName: 'مدخل', role: 'DATA_ENTRY' }, T);
  let de = await h.login('de1', 'Data1234x');
  await h.api('PUT', '/auth/profile', { oldPassword: 'Data1234x', newPassword: 'Data5678x' }, de.token);
  const oldTokenUse = await h.api('GET', '/auth/me', undefined, de.token);
  assert.equal(oldTokenUse.status, 401);
  de = await h.login('de1', 'Data5678x');
  await h.api('PUT', `/settings/users/${de.user.id}`, { newPassword: 'Reset1234x' }, T);
  const afterAdminReset = await h.api('GET', '/auth/me', undefined, de.token);
  assert.equal(afterAdminReset.status, 401);
});

test('password policy is enforced on user creation', async () => {
  const r = await h.api('POST', '/settings/users', { username: 'weak', password: '1', fullName: 'ضعيف', role: 'DATA_ENTRY' }, T);
  assert.equal(r.status, 400);
});

test('super admin cannot deactivate or demote self, and last super admin is protected', async () => {
  const me = (await h.api('GET', '/auth/me', undefined, T)).body.data.user;
  let r = await h.api('PUT', `/settings/users/${me.id}`, { isActive: false }, T);
  assert.equal(r.status, 400);
  r = await h.api('PUT', `/settings/users/${me.id}`, { role: 'DATA_ENTRY' }, T);
  assert.equal(r.status, 400);

  await h.api('POST', '/settings/users', { username: 'sa2', password: 'Super1234x', fullName: 'أدمن 2', role: 'SUPER_ADMIN' }, T);
  const sa2id = h.db.prepare("SELECT id FROM users WHERE username='sa2'").get().id;
  // إزالة الأدمن الثاني مسموحة لأن الأول ما زال نشطاً
  r = await h.api('PUT', `/settings/users/${sa2id}`, { role: 'DATA_ENTRY' }, T);
  assert.equal(r.status, 200);
  const admins = h.db.prepare("SELECT COUNT(*) c FROM users WHERE role='SUPER_ADMIN' AND is_active=1 AND deleted_at IS NULL").get().c;
  assert.ok(admins >= 1);
});

test('settings reject unknown keys and invalid times', async () => {
  let r = await h.api('PUT', '/settings', { work_start_time: 'abc' }, T);
  assert.equal(r.status, 400);
  r = await h.api('PUT', '/settings', { some_random_key: 'x' }, T);
  assert.equal(r.status, 400);
  r = await h.api('PUT', '/settings', { work_start_time: '16:00', work_end_time: '15:00' }, T);
  assert.equal(r.status, 400);
  r = await h.api('PUT', '/settings', { work_start_time: '09:30', bonus_enabled: 'true' }, T);
  assert.equal(r.status, 200);
  await h.api('PUT', '/settings', { work_start_time: '10:00' }, T);
});

test('security headers present and x-powered-by hidden', async () => {
  const res = await fetch(`${h.base}/system/status`);
  assert.ok(res.headers.get('x-content-type-options'));
  assert.equal(res.headers.get('x-powered-by'), null);
});

test('reveal password requires correct admin password verified by server', async () => {
  const id = h.db.prepare("SELECT id FROM users WHERE username='de1'").get().id;
  let r = await h.api('POST', `/settings/users/${id}/reveal-password`, { adminPassword: 'wrong' }, T);
  assert.equal(r.status, 403);
  r = await h.api('POST', `/settings/users/${id}/reveal-password`, { adminPassword: h.ADMIN_PASSWORD }, T);
  assert.equal(r.status, 200);
  assert.equal(r.body.data.password, 'Reset1234x');
});

test('verify-password accepts only the current user password', async () => {
  await h.api('POST', '/settings/users', { username: 'de9', password: 'Data9999x', fullName: 'مدخل 9', role: 'DATA_ENTRY' }, T);
  let de = await h.login('de9', 'Data9999x');
  // مستخدم جديد أنشأه الأدمن مُلزم بتغيير كلمة المرور
  await h.api('PUT', '/auth/profile', { oldPassword: 'Data9999x', newPassword: 'Data8888x' }, de.token);
  de = await h.login('de9', 'Data8888x');
  let r = await h.api('POST', '/auth/verify-password', { password: h.ADMIN_PASSWORD }, de.token);
  assert.equal(r.status, 403);
  r = await h.api('POST', '/auth/verify-password', { password: 'Data8888x' }, de.token);
  assert.equal(r.status, 200);
});

test('download tickets: required, short-lived, bound to params', async () => {
  const noTicket = await fetch(`${h.base}/reports/export-daily?date=2026-10-20`);
  assert.equal(noTicket.status, 401);
  const t = await h.api('POST', '/downloads/ticket', { kind: 'export-daily', params: { date: '2026-10-20' } }, T);
  assert.equal(t.status, 200);
  const ok = await fetch(`${h.base}/reports/export-daily?date=2026-10-20&ticket=${t.body.data.ticket}`);
  assert.equal(ok.status, 200);
  const tampered = await fetch(`${h.base}/reports/export-daily?date=2026-10-21&ticket=${t.body.data.ticket}`);
  assert.equal(tampered.status, 401);
});

test('deleted user is soft-deleted and keeps history', async () => {
  const id = h.db.prepare("SELECT id FROM users WHERE username='sa2'").get().id;
  const r = await h.api('DELETE', `/settings/users/${id}`, undefined, T);
  assert.equal(r.status, 200);
  const row = h.db.prepare('SELECT deleted_at, is_active FROM users WHERE id = ?').get(id);
  assert.ok(row.deleted_at);
  assert.equal(row.is_active, 0);
});
