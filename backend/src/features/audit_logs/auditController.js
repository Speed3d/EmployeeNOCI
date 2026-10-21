/**
 * Hint: متحكم سجل الحركات والتدقيق الأمني (Audit Logs)
 * يتيح للسوبر أدمن مراقبة كل حركة، المستخدم الذي قام بها، تفاصيلها، تاريخها، وعنوان الـ IP
 */
const db = require('../../core/database');
const { successResponse } = require('../../shared/responseHelper');

function listAuditLogs(req, res) {
  const { userId, action, search, startDate, endDate, limit = 100, page = 1 } = req.query;

  let query = 'SELECT * FROM audit_logs WHERE 1=1';
  const params = [];

  if (userId) {
    query += ' AND user_id = ?';
    params.push(userId);
  }

  if (action) {
    query += ' AND action LIKE ?';
    params.push(`%${action.trim()}%`);
  }

  if (search) {
    query += ' AND (user_name LIKE ? OR details LIKE ? OR action LIKE ?)';
    const term = `%${search.trim()}%`;
    params.push(term, term, term);
  }

  if (startDate) {
    query += ' AND created_at >= ?';
    params.push(`${startDate} 00:00:00`);
  }

  if (endDate) {
    query += ' AND created_at <= ?';
    params.push(`${endDate} 23:59:59`);
  }

  // حساب الإجمالي
  const countQuery = query.replace('SELECT *', 'SELECT COUNT(*) as total');
  const total = db.prepare(countQuery).get(...params).total;

  const pageSize = parseInt(limit, 10) || 50;
  const offset = (parseInt(page, 10) - 1) * pageSize;

  query += ' ORDER BY id DESC LIMIT ? OFFSET ?';
  params.push(pageSize, offset);

  const logs = db.prepare(query).all(...params);

  return successResponse(res, {
    total,
    page: parseInt(page, 10),
    pageSize,
    logs
  });
}

module.exports = {
  listAuditLogs
};
