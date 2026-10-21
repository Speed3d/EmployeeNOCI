/**
 * Hint: مسارات سجل الحركات والتدقيق
 */
const express = require('express');
const router = express.Router();
const auditController = require('./auditController');
const { authenticateToken, requireSuperAdmin } = require('../../core/authMiddleware');

router.get('/', authenticateToken, requireSuperAdmin, auditController.listAuditLogs);

module.exports = router;
