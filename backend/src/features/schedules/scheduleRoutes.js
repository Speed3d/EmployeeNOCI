/**
 * Hint: مسارات قوالب وجداول دوام الموظفين وأيام الراحة الأسبوعية
 */
const express = require('express');
const router = express.Router();
const scheduleController = require('./scheduleController');
const { authenticateToken, requireRoles } = require('../../core/authMiddleware');
const { ROLES } = require('../../shared/constants');

// قوالب الدوام
router.get('/templates', authenticateToken, scheduleController.listTemplates);
router.post('/templates', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), scheduleController.createTemplate);
router.put('/templates/:id', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), scheduleController.updateTemplate);
router.delete('/templates/:id', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), scheduleController.deleteTemplate);

// جداول دوام الموظفين والربط الأسبوعي
router.get('/assignments', authenticateToken, scheduleController.getAssignments);
router.post('/assign', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), scheduleController.assignSchedule);
router.post('/copy-previous-week', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), scheduleController.copyPreviousWeek);

module.exports = router;
