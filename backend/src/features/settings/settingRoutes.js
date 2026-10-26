/**
 * Hint: مسارات لوحة الإعدادات، المستخدمين، كشف كلمات المرور، والتصفير (حصرياً للسوبر أدمن)
 */
const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const settingController = require('./settingController');
const { authenticateToken, requireSuperAdmin } = require('../../core/authMiddleware');
const { UPLOADS_DIR } = require('../../core/config');

// إعداد مجلد تخزين الشعار
const brandingDir = path.join(UPLOADS_DIR, 'branding');
if (!fs.existsSync(brandingDir)) {
  fs.mkdirSync(brandingDir, { recursive: true });
}

// Hint: السماح فقط بامتدادات الصور الآمنة لشعار المؤسسة
const ALLOWED_LOGO_EXTS = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif']);

const logoStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, brandingDir),
  filename: (req, file, cb) => {
    const rawExt = path.extname(file.originalname || '').toLowerCase();
    const safeExt = ALLOWED_LOGO_EXTS.has(rawExt) ? rawExt : '.png';
    cb(null, `logo_${Date.now()}${safeExt}`);
  }
});
const uploadLogo = multer({
  storage: logoStorage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    if (!ALLOWED_LOGO_EXTS.has(ext)) {
      return cb(new Error('يُسمح فقط برفع ملفات الصور للشعار (PNG, JPG, WEBP, GIF)'));
    }
    cb(null, true);
  }
});

// 1. الإعدادات العامة (عرض للجميع ومصادقة، والتعديل حصري للسوبر أدمن)
router.get('/', authenticateToken, settingController.getSettings);
router.put('/', authenticateToken, requireSuperAdmin, settingController.updateSettings);
router.post('/logo', authenticateToken, requireSuperAdmin, uploadLogo.single('file'), settingController.uploadLogo);

// 2. إدارة المستخدمين (حصرياً للسوبر أدمن)
router.get('/users', authenticateToken, requireSuperAdmin, settingController.listUsers);
router.post('/users', authenticateToken, requireSuperAdmin, settingController.createUser);
router.put('/users/:id', authenticateToken, requireSuperAdmin, settingController.updateUser);
router.delete('/users/:id', authenticateToken, requireSuperAdmin, settingController.deleteUser);
router.get('/users/:id/reveal-password', authenticateToken, requireSuperAdmin, settingController.revealPassword);

// 3. تصفير النظام وإعادة الضبط (حصرياً للسوبر أدمن)
router.post('/reset-db', authenticateToken, requireSuperAdmin, settingController.resetDatabase);

// 4. الترحيل السنوي (حصرياً للسوبر أدمن)
router.post('/switch-year', authenticateToken, requireSuperAdmin, settingController.switchActiveYear);

module.exports = router;
