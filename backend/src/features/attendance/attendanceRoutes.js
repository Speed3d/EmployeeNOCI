/**
 * Hint: مسارات كشوفات البصمة والحضور اليومي والمعاينة والاعتماد
 */
const express = require('express');
const router = express.Router();
const multer = require('multer');
const attendanceController = require('./attendanceController');
const { authenticateToken, requireRoles } = require('../../core/authMiddleware');
const { ROLES } = require('../../shared/constants');

// رفع الملفات في الذاكرة لتسريع التحليل
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 25 * 1024 * 1024 } // حتى 25 ميغابايت
});

// معاينة الكشف بدون حفظ (سوبر أدمن ومدخل بيانات)
router.post('/preview', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), upload.single('file'), attendanceController.previewAttendance);

// اعتماد وحفظ الكشف في القاعدة (سوبر أدمن ومدخل بيانات)
router.post('/commit', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), attendanceController.commitAttendance);

// فحص حالة اليوم
router.get('/check-status', authenticateToken, attendanceController.checkDayStatus);

// جلب كشف الحضور ليوم محدد
router.get('/daily', authenticateToken, attendanceController.getDailyAttendance);

// إعادة احتساب واعتماد يوم معتمد
router.post('/recalculate', authenticateToken, attendanceController.recalculateDay);

module.exports = router;
