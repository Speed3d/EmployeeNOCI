/**
 * Hint: مسارات الموظفين والأقسام ونقل الموظفين والاستيراد
 */
const express = require('express');
const router = express.Router();
const multer = require('multer');
const employeeController = require('./employeeController');
const { authenticateToken, requireSuperAdmin } = require('../../core/authMiddleware');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 20 * 1024 * 1024 }
});

// قائمة وعرض الموظفين (متاح للجميع بعد المصادقة)
router.get('/', authenticateToken, employeeController.listEmployees);
router.get('/departments', authenticateToken, employeeController.listDepartments);
router.get('/:id', authenticateToken, employeeController.getEmployee);

// تعديل استبعاد الأقسام (سوبر أدمن أو من يملك صلاحية)
router.put('/departments/:id/exclusion', authenticateToken, employeeController.toggleDepartmentExclusion);

// إدارة الموظفين ونقلهم واستيرادهم (حصرياً للسوبر أدمن)
router.post('/', authenticateToken, requireSuperAdmin, employeeController.createEmployee);
router.put('/:id', authenticateToken, requireSuperAdmin, employeeController.updateEmployee);
router.delete('/:id', authenticateToken, requireSuperAdmin, employeeController.deleteEmployee);
router.post('/:id/transfer', authenticateToken, requireSuperAdmin, employeeController.transferEmployee);
router.put('/:id/vip-exempt', authenticateToken, requireSuperAdmin, employeeController.toggleVipExempt);
router.post('/import-excel', authenticateToken, requireSuperAdmin, upload.single('file'), employeeController.importEmployeesExcel);

module.exports = router;
