/**
 * Hint: متحكم سجل الحركات والتدقيق الأمني (Audit Logs)
 * يتيح للسوبر أدمن مراقبة كل حركة، المستخدم الذي قام بها، تفاصيلها، تاريخها، وعنوان الـ IP
 */
const db = require('../../core/database');
const { successResponse } = require('../../shared/responseHelper');
const { baghdadDayBoundsUtc } = require('../../tools/timeUtils');
const { isYmd, toPositiveInt, badRequest } = require('../../shared/validators');

function listAuditLogs(req, res) {
  const { userId, action, search, startDate, endDate, limit = 100, page = 1 } = req.query;

  let query = 'SELECT * FROM audit_logs WHERE 1=1';
  const params = [];

  if (userId) {
    const uid = toPositiveInt(userId);
    if (!uid) return badRequest(res, 'معرف المستخدم غير صالح');
    query += ' AND user_id = ?';
    params.push(uid);
  }

  if (action) {
    query += ' AND action LIKE ?';
    params.push(`%${String(action).trim()}%`);
  }

  if (search) {
    query += ' AND (user_name LIKE ? OR details LIKE ? OR action LIKE ?)';
    const term = `%${String(search).trim()}%`;
    params.push(term, term, term);
  }

  // Hint: التواريخ المدخلة بتوقيت بغداد تُحوَّل إلى UTC لأن created_at محفوظ بتوقيت UTC
  if (startDate) {
    if (!isYmd(startDate)) return badRequest(res, 'تاريخ البداية غير صالح');
    query += ' AND created_at >= ?';
    params.push(baghdadDayBoundsUtc(startDate)[0]);
  }

  if (endDate) {
    if (!isYmd(endDate)) return badRequest(res, 'تاريخ النهاية غير صالح');
    query += ' AND created_at <= ?';
    params.push(baghdadDayBoundsUtc(endDate)[1]);
  }

  // حساب الإجمالي
  const countQuery = query.replace('SELECT *', 'SELECT COUNT(*) as total');
  const total = db.prepare(countQuery).get(...params).total;

  const pageSize = Math.min(toPositiveInt(limit) || 50, 500);
  const pageNum = toPositiveInt(page) || 1;
  const offset = (pageNum - 1) * pageSize;

  query += ' ORDER BY id DESC LIMIT ? OFFSET ?';
  params.push(pageSize, offset);

  const logs = db.prepare(query).all(...params);

  return successResponse(res, {
    total,
    page: pageNum,
    pageSize,
    logs
  });
}

module.exports = {
  listAuditLogs
};
