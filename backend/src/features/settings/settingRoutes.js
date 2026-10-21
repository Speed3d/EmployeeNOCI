/**
 * Hint: مسارات إعدادات النظام والمستخدمين (حصرياً للسوبر أدمن)
 */
const express = require('express');
const router = express.Router();
const settingController = require('./settingController');
const { authenticateToken, requireSuperAdmin } = require('../../core/authMiddleware');

// قراءة الإعدادات متاحة لجميع المستخدمين المسجلين (لعرض الشعار والاسم)
router.get('/', authenticateToken, settingController.getSettings);

// تعديل الإعدادات والتحكم بالمستخدمين محصور بالسوبر أدمن
router.put('/', authenticateToken, requireSuperAdmin, settingController.updateSettings);

router.get('/users', authenticateToken, requireSuperAdmin, settingController.listUsers);
router.post('/users', authenticateToken, requireSuperAdmin, settingController.createUser);
router.put('/users/:id', authenticateToken, requireSuperAdmin, settingController.updateUser);
router.delete('/users/:id', authenticateToken, requireSuperAdmin, settingController.deleteUser);

router.post('/switch-year', authenticateToken, requireSuperAdmin, settingController.switchActiveYear);

module.exports = router;
