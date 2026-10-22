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

// إعداد مجلد تخزين الصور الشخصية
const avatarsDir = path.join(UPLOADS_DIR, 'avatars');
if (!fs.existsSync(avatarsDir)) {
  fs.mkdirSync(avatarsDir, { recursive: true });
}

const avatarStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, avatarsDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.png';
    cb(null, `avatar_${req.user.id}_${Date.now()}${ext}`);
  }
});
const uploadAvatar = multer({ storage: avatarStorage, limits: { fileSize: 5 * 1024 * 1024 } });

router.post('/login', authController.login);
router.get('/me', authenticateToken, authController.getMe);
router.put('/profile', authenticateToken, authController.updateProfile);
router.post('/avatar', authenticateToken, uploadAvatar.single('file'), authController.uploadAvatar);

module.exports = router;
