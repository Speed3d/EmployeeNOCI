/**
 * Hint: إصدار تذاكر تنزيل قصيرة العمر (60 ثانية) بدل تمرير رمز الجلسة في الروابط
 * التذكرة مرتبطة بنوع الملف ومعاملاته، فلا تصلح لتنزيل ملف آخر ولا للمصادقة العامة
 */
const express = require('express');
const jwt = require('jsonwebtoken');
const router = express.Router();
const { JWT_SECRET } = require('../../core/config');
const { authenticateToken } = require('../../core/authMiddleware');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { ROLES } = require('../../shared/constants');

// Hint: أنواع التنزيل المسموحة ومساراتها ومعاملاتها ومن يحق له طلبها
const DOWNLOAD_KINDS = {
  'export-daily': { path: '/reports/export-daily', params: ['date', 'department', 'status'] },
  'export-monthly': { path: '/reports/export-monthly', params: ['year', 'month', 'department'] },
  backup: { path: '/backup/download', params: ['filename'], superAdminOnly: true }
};

router.post('/ticket', authenticateToken, (req, res) => {
  const { kind } = req.body;
  const spec = DOWNLOAD_KINDS[kind];
  if (!spec) {
    return errorResponse(res, 'نوع التنزيل غير معروف', 400);
  }
  if (spec.superAdminOnly && req.user.role !== ROLES.SUPER_ADMIN) {
    return errorResponse(res, 'عذراً، هذا التنزيل محصور بالسوبر أدمن فقط', 403);
  }

  const input = req.body.params && typeof req.body.params === 'object' ? req.body.params : {};
  const params = {};
  const query = new URLSearchParams();
  for (const p of spec.params) {
    if (input[p] === undefined || input[p] === null || input[p] === '') continue;
    params[p] = String(input[p]).slice(0, 200);
    query.set(p, params[p]);
  }

  const ticket = jwt.sign(
    { purpose: 'download', kind, params, uid: req.user.id, tv: req.user.token_version },
    JWT_SECRET,
    { expiresIn: '60s' }
  );
  query.set('ticket', ticket);

  return successResponse(res, { ticket, url: `${spec.path}?${query.toString()}`, expiresInSeconds: 60 });
});

module.exports = router;
