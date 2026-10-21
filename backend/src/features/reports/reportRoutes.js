/**
 * Hint: مسارات التقارير والتصدير
 */
const express = require('express');
const router = express.Router();
const reportController = require('./reportController');
const { authenticateToken } = require('../../core/authMiddleware');

router.get('/monthly', authenticateToken, reportController.getMonthlyTimesheet);
router.get('/export-daily-excel', authenticateToken, reportController.exportDailyExcel);

module.exports = router;
