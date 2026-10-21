/**
 * Hint: مسارات الإجازات والعطلات
 */
const express = require('express');
const router = express.Router();
const leaveController = require('./leaveController');
const { authenticateToken, requireRoles } = require('../../core/authMiddleware');
const { ROLES } = require('../../shared/constants');

// الإجازات
router.get('/', authenticateToken, leaveController.listLeaves);
router.post('/', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.HR_MANAGER, ROLES.DATA_ENTRY]), leaveController.createLeave);
router.delete('/:id', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.HR_MANAGER]), leaveController.deleteLeave);

// العطل الرسمية
router.get('/holidays', authenticateToken, leaveController.listHolidays);
router.post('/holidays', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.HR_MANAGER]), leaveController.createHoliday);
router.delete('/holidays/:id', authenticateToken, requireRoles([ROLES.SUPER_ADMIN]), leaveController.deleteHoliday);

module.exports = router;
