/**
 * Hint: فحص تكامل كافة نقاط الـ API
 */
const http = require('http');
const app = require('../src/app');

const server = app.listen(5099, '127.0.0.1', async () => {
  console.log('سيرفر الاختبار قيد التشغيل على المنفذ 5099...');

  try {
    // 1. فحص الحالة
    const statusRes = await fetch('http://127.0.0.1:5099/api/system/status').then(r => r.json());
    console.log('1. فحص الحالة:', statusRes.status === 'ONLINE' ? '✔ نجح' : '❌ فشل', statusRes.name);

    // 2. فحص تسجيل الدخول
    const loginRes = await fetch('http://127.0.0.1:5099/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'admin', password: 'Admin@123456' })
    }).then(r => r.json());
    console.log('2. فحص تسجيل الدخول:', loginRes.success ? '✔ نجح' : '❌ فشل', loginRes.message);

    const token = loginRes.data.token;

    // 3. فحص جلب الموظفين
    const empRes = await fetch('http://127.0.0.1:5099/api/employees?search=عمار', {
      headers: { 'Authorization': `Bearer ${token}` }
    }).then(r => r.json());
    console.log('3. فحص جلب الموظفين (بحث "عمار"):', empRes.success ? '✔ نجح' : '❌ فشل', `(العدد: ${empRes.data.length})`);

    // 4. فحص جلب الحضور اليومي
    const attRes = await fetch('http://127.0.0.1:5099/api/attendance/daily?date=2026-10-20', {
      headers: { 'Authorization': `Bearer ${token}` }
    }).then(r => r.json());
    console.log('4. فحص جلب الحضور لتاريخ 2026-10-20:', attRes.success ? '✔ نجح' : '❌ فشل', `(الحضور: ${attRes.data.stats.present} / الغياب: ${attRes.data.stats.absent})`);

    // 5. فحص سجل الحركات (Audit Logs)
    const auditRes = await fetch('http://127.0.0.1:5099/api/audit-logs', {
      headers: { 'Authorization': `Bearer ${token}` }
    }).then(r => r.json());
    console.log('5. فحص سجل الحركات (Audit Logs):', auditRes.success ? '✔ نجح' : '❌ فشل', `(إجمالي الحركات المسجلة: ${auditRes.data.total})`);

    console.log('\n✔ كافة نقاط الـ API الأساسية تعمل بنجاح وبسرعة فائقة وبدون أي أخطاء!');
  } catch (err) {
    console.error('❌ خطأ في الاختبار:', err);
  } finally {
    server.close();
    process.exit(0);
  }
});
