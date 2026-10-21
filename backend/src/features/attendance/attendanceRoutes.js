/**
 * Hint: مسارات كشوفات البصمة والحضور اليومي
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
  limits: { fileSize: 15 * 1024 * 1024 } // حتى 15 ميغابايت
});

router.post('/upload', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.HR_MANAGER, ROLES.DATA_ENTRY]), upload.single('file'), attendanceController.uploadDailyAttendance);
router.get('/daily', authenticateToken, attendanceController.getDailyAttendance);
router.post('/recalculate', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.HR_MANAGER]), attendanceController.recalculateDay);

module.exports = router;
