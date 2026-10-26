/**
 * Hint: مسارات التقارير الشاملة الشهرية وتصدير الإكسل
 */
const express = require('express');
const router = express.Router();
const reportController = require('./reportController');
const { authenticateToken } = require('../../core/authMiddleware');

router.get('/monthly', authenticateToken, reportController.getMonthlyTimesheet);
router.post('/export-excel', authenticateToken, reportController.exportGenericExcel);
router.get('/export-daily', authenticateToken, reportController.exportDailyExcel);
router.get('/export-monthly', authenticateToken, reportController.exportMonthlyExcel);

module.exports = router;
