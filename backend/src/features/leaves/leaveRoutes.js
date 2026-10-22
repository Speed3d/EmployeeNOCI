/**
 * Hint: مسارات الإجازات والأذونات والعطل الرسمية
 */
const express = require('express');
const router = express.Router();
const leaveController = require('./leaveController');
const { authenticateToken, requireSuperAdmin, requireRoles } = require('../../core/authMiddleware');
const { ROLES } = require('../../shared/constants');

// الإجازات (سوبر أدمن ومدخل بيانات)
router.get('/', authenticateToken, leaveController.listLeaves);
router.post('/', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), leaveController.createLeave);
router.delete('/:id', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), leaveController.deleteLeave);

// العطل الرسمية (عرض للجميع، وإضافة/حذف حصراً للسوبر أدمن)
router.get('/holidays', authenticateToken, leaveController.listHolidays);
router.post('/holidays', authenticateToken, requireSuperAdmin, leaveController.createHoliday);
router.delete('/holidays/:id', authenticateToken, requireSuperAdmin, leaveController.deleteHoliday);

module.exports = router;
