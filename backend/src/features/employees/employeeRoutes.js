/**
 * Hint: مسارات الموظفين والأقسام
 */
const express = require('express');
const router = express.Router();
const employeeController = require('./employeeController');
const { authenticateToken, requireRoles } = require('../../core/authMiddleware');
const { ROLES } = require('../../shared/constants');

// العمليات المتاحة
router.get('/', authenticateToken, employeeController.listEmployees);
router.get('/departments', authenticateToken, employeeController.listDepartments);
router.put('/departments/:id/toggle-exclusion', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.HR_MANAGER]), employeeController.toggleDepartmentExclusion);

router.get('/:id', authenticateToken, employeeController.getEmployee);
router.post('/', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.HR_MANAGER]), employeeController.createEmployee);
router.put('/:id', authenticateToken, requireRoles([ROLES.SUPER_ADMIN, ROLES.HR_MANAGER]), employeeController.updateEmployee);
router.delete('/:id', authenticateToken, requireRoles([ROLES.SUPER_ADMIN]), employeeController.deleteEmployee);
router.put('/:id/toggle-exempt', authenticateToken, requireRoles([ROLES.SUPER_ADMIN]), employeeController.toggleVipExempt);

module.exports = router;
