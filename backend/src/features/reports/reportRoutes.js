/**
 * Hint: مسارات التقارير الشاملة الشهرية وتصدير الإكسل
 */
const express = require('express');
const router = express.Router();
const reportController = require('./reportController');
const { authenticateToken, authenticateDownloadTicket } = require('../../core/authMiddleware');

router.get('/monthly', authenticateToken, reportController.getMonthlyTimesheet);
router.post('/export-excel', authenticateToken, reportController.exportGenericExcel);
// Hint: روابط التنزيل المباشر تُصادق بتذكرة قصيرة العمر من /api/downloads/ticket
router.get('/export-daily', authenticateDownloadTicket('export-daily', ['date', 'department', 'status']), reportController.exportDailyExcel);
router.get('/export-monthly', authenticateDownloadTicket('export-monthly', ['year', 'month', 'department']), reportController.exportMonthlyExcel);

module.exports = router;
