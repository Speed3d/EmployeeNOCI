/**
 * Hint: مسارات النسخ الاحتياطي والاستعادة الفورية لقاعدة البيانات (حصري للسوبر أدمن)
 */
const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const backupController = require('./backupController');
const { authenticateToken, requireSuperAdmin } = require('../../core/authMiddleware');

// Hint: مجلد الرفع المؤقت بجوار قاعدة البيانات (data/temp_uploads)
const { DB_PATH } = require('../../core/config');
const tempUploadDir = path.join(path.dirname(DB_PATH), 'temp_uploads');
if (!fs.existsSync(tempUploadDir)) {
  fs.mkdirSync(tempUploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, tempUploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.db';
    cb(null, `restore_${Date.now()}${ext}`);
  }
});
const upload = multer({
  storage,
  limits: { fileSize: 100 * 1024 * 1024 } // حتى 100 ميغابايت لقاعدة البيانات
});

// كافة مسارات النسخ الاحتياطي تتطلب أن يكون المستخدم SUPER_ADMIN حصراً
router.use(authenticateToken, requireSuperAdmin);

router.get('/', backupController.listBackups);
router.post('/create', backupController.createBackup);
router.get('/download', backupController.downloadBackup);
router.post('/restore', upload.single('file'), backupController.restoreBackup);
router.delete('/:filename', backupController.deleteBackup);

module.exports = router;
