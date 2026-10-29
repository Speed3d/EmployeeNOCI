/**
 * Hint: اختبارات المحادثة والنسخ الاحتياطي والتوقيت
 */
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const h = require('./helpers');
const { baghdadDayBoundsUtc } = require('../src/tools/timeUtils');

let T;
let de;

before(async () => {
  await h.start();
  T = await h.adminToken();
  await h.api('POST', '/settings/users', { username: 'chatter', password: 'Chat1234x', fullName: 'محاور', role: 'DATA_ENTRY' }, T);
  const first = await h.login('chatter', 'Chat1234x');
  await h.api('PUT', '/auth/profile', { oldPassword: 'Chat1234x', newPassword: 'Chat5678x' }, first.token);
  de = await h.login('chatter', 'Chat5678x');
});
after(h.stop);

test('chat returns the latest messages and supports loading older ones', async () => {
  const adminId = h.db.prepare("SELECT id FROM users WHERE username='admin'").get().id;
  const ins = h.db.prepare('INSERT INTO chat_messages (sender_id, sender_name, receiver_id, message) VALUES (?, ?, ?, ?)');
  h.db.transaction(() => { for (let i = 0; i < 200; i++) ins.run(adminId, 'admin', de.user.id, 'msg ' + i); })();
  const r = await h.api('GET', `/chat/messages?type=DIRECT&targetId=${adminId}`, undefined, de.token);
  assert.equal(r.body.data.length, 150);
  assert.equal(r.body.data[r.body.data.length - 1].message, 'msg 199');
  assert.equal(r.body.data[0].message, 'msg 50');
  const older = await h.api('GET', `/chat/messages?type=DIRECT&targetId=${adminId}&beforeId=${r.body.data[0].id}`, undefined, de.token);
  assert.equal(older.body.data.length, 50);
  assert.equal(older.body.data[49].message, 'msg 49');
});

test('group creation with invalid member is rejected atomically', async () => {
  const before = h.db.prepare('SELECT COUNT(*) c FROM chat_channels').get().c;
  const r = await h.api('POST', '/chat/groups', { name: 'g', memberIds: [99999] }, T);
  assert.equal(r.status, 400);
  assert.equal(h.db.prepare('SELECT COUNT(*) c FROM chat_channels').get().c, before);
});

test('direct message to a non-existent user or self is rejected; long messages rejected', async () => {
  let r = await h.api('POST', '/chat/messages', { type: 'DIRECT', targetId: 424242, message: 'hi' }, de.token);
  assert.equal(r.status, 404);
  r = await h.api('POST', '/chat/messages', { type: 'DIRECT', targetId: de.user.id, message: 'hi' }, de.token);
  assert.equal(r.status, 400);
  r = await h.api('POST', '/chat/messages', { type: 'DIRECT', targetId: 1, message: 'x'.repeat(2001) }, de.token);
  assert.equal(r.status, 400);
});

test('reset is aborted when the safety backup fails', async () => {
  const backupsDir = path.join(path.dirname(process.env.DB_PATH), 'backups');
  // جعل مسار النسخ ملفاً عادياً يجعل إنشاء النسخة يفشل
  fs.rmSync(backupsDir, { recursive: true, force: true });
  fs.writeFileSync(backupsDir, 'block');
  const users = h.db.prepare('SELECT COUNT(*) c FROM users').get().c;
  const r = await h.api('POST', '/settings/reset-db', { password: h.ADMIN_PASSWORD, resetMode: 'wipe_all' }, T);
  assert.equal(r.status, 500);
  assert.equal(h.db.prepare('SELECT COUNT(*) c FROM users').get().c, users);
  fs.rmSync(backupsDir, { force: true });
  fs.mkdirSync(backupsDir);
});

test('restore rejects a SQLite file without the system tables', async () => {
  const Database = require('better-sqlite3');
  const foreign = path.join(path.dirname(process.env.DB_PATH), 'foreign.db');
  const fdb = new Database(foreign);
  fdb.exec('CREATE TABLE x (a)');
  fdb.close();
  const r = await h.upload('/backup/restore', foreign, T);
  assert.equal(r.status, 400);
});

test('Baghdad day bounds convert to UTC', () => {
  assert.deepEqual(baghdadDayBoundsUtc('2026-10-29'), ['2026-10-28 21:00:00', '2026-10-29 20:59:59']);
});
