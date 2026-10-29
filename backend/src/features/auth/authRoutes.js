/**
 * Hint: مسارات المصادقة والملف الشخصي وتحديث الصور
 */
const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const authController = require('./authController');
const { authenticateToken } = require('../../core/authMiddleware');
const { UPLOADS_DIR } = require('../../core/config');
const { httpError } = require('../../shared/responseHelper');

// إعداد مجلد تخزين الصور الشخصية
const avatarsDir = path.join(UPLOADS_DIR, 'avatars');
if (!fs.existsSync(avatarsDir)) {
  fs.mkdirSync(avatarsDir, { recursive: true });
}

// Hint: الامتدادات المسموحة للصور الشخصية لمنع رفع أي ملفات تنفيذية أو برمجية ضارة
const ALLOWED_IMAGE_EXTS = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif']);

const avatarStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, avatarsDir),
  filename: (req, file, cb) => {
    const rawExt = path.extname(file.originalname || '').toLowerCase();
    const safeExt = ALLOWED_IMAGE_EXTS.has(rawExt) ? rawExt : '.png';
    cb(null, `avatar_${req.user.id}_${Date.now()}${safeExt}`);
  }
});

const uploadAvatar = multer({
  storage: avatarStorage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    if (!ALLOWED_IMAGE_EXTS.has(ext)) {
      return cb(httpError(400, 'يُسمح فقط برفع ملفات الصور (PNG, JPG, WEBP, GIF)'));
    }
    cb(null, true);
  }
});

router.post('/login', authController.login);
router.get('/me', authenticateToken, authController.getMe);
router.put('/profile', authenticateToken, authController.updateProfile);
router.post('/avatar', authenticateToken, uploadAvatar.single('file'), authController.uploadAvatar);
router.post('/verify-password', authenticateToken, authController.verifyPassword);

module.exports = router;
