/**
 * Hint: مسارات قوالب وجداول دوام الموظفين وأيام الراحة الأسبوعية
 */
const express = require('express');
const router = express.Router();
const scheduleController = require('./scheduleController');
const { authenticateToken, requireRoles, requireSuperAdmin } = require('../../core/authMiddleware');
const { ROLES } = require('../../shared/constants');

// Hint: قوالب الدوام - استعراض للجميع، وإنشاء/تعديل/حذف حصرياً للمدير العام (SUPER_ADMIN)
router.get('/templates', authenticateToken, scheduleController.listTemplates);
router.post('/templates', authenticateToken, requireSuperAdmin, scheduleController.createTemplate);
router.put('/templates/:id', authenticateToken, requireSuperAdmin, scheduleController.updateTemplate);
router.delete('/templates/:id', authenticateToken, requireSuperAdmin, scheduleController.deleteTemplate);

// جداول دوام الموظفين والربط الأسبوعي
router.get('/assignments', authenticateToken, scheduleController.getAssignments);
router.post('/assign', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), scheduleController.assignSchedule);
router.post('/copy-previous-week', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.DATA_ENTRY]), scheduleController.copyPreviousWeek);

module.exports = router;
