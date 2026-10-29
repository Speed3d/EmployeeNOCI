/**
 * Hint: متحكم النسخ الاحتياطي والاستعادة الفورية لقاعدة بيانات النظام
 * يتيح للسوبر أدمن إنشاء نسخ احتياطية محلياً، تنزيلها إلى جهازه، استعادتها بأمان تام، وإدارتها
 */
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { BACKUPS_DIR, createBackupFile } = require('../../core/backupScheduler');

// Hint: الجداول التي يجب أن تحتويها أي نسخة احتياطية صالحة لهذا النظام
const REQUIRED_TABLES = ['users', 'employees', 'attendance_records', 'attendance_days', 'system_settings'];

function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatDate(date) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Baghdad',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  }).format(date).replace(',', '');
}

/**
 * 1. جلب قائمة النسخ الاحتياطية المحفوظة محلياً
 */
function listBackups(req, res) {
  try {
    if (!fs.existsSync(BACKUPS_DIR)) {
      return successResponse(res, []);
    }

    const files = fs.readdirSync(BACKUPS_DIR);
    const backups = [];

    for (const file of files) {
      if (!file.endsWith('.db')) continue;
      const filePath = path.join(BACKUPS_DIR, file);
      const stat = fs.statSync(filePath);

      backups.push({
        filename: file,
        sizeBytes: stat.size,
        sizeFormatted: formatBytes(stat.size),
        createdAt: formatDate(stat.mtime),
        timestamp: stat.mtimeMs
      });
    }

    // الترتيب من الأحدث للأقدم
    backups.sort((a, b) => b.timestamp - a.timestamp);

    return successResponse(res, backups);
  } catch (err) {
    return errorResponse(res, `فشل قراءة قائمة النسخ الاحتياطية: ${err.message}`, 500);
  }
}

/**
 * 2. إنشاء نسخة احتياطية جديدة وحفظها في مجلد النسخ
 */
async function createBackup(req, res) {
  const user = req.user;
  try {
    const { filename, destPath, size } = await createBackupFile('backup_noci_');
    const stat = fs.statSync(destPath);

    logAction(user.id, user.full_name, 'إنشاء نسخة احتياطية', `تم إنشاء نسخة احتياطية جديدة: ${filename} بحجم ${formatBytes(size)}`, req.clientIp);

    return successResponse(res, {
      filename,
      sizeBytes: size,
      sizeFormatted: formatBytes(size),
      createdAt: formatDate(stat.mtime)
    }, 'تم إنشاء النسخة الاحتياطية بنجاح');
  } catch (err) {
    console.error('فشل إنشاء النسخة الاحتياطية:', err);
    return errorResponse(res, 'فشل إنشاء النسخة الاحتياطية', 500);
  }
}

/**
 * 3. تنزيل نسخة احتياطية مباشرة لجهاز المستخدم
 */
async function downloadBackup(req, res) {
  const { filename } = req.query;
  try {
    let filePath;
    let downloadName;

    if (filename && filename !== 'current') {
      const safeName = path.basename(filename);
      filePath = path.join(BACKUPS_DIR, safeName);
      if (!fs.existsSync(filePath)) {
        return errorResponse(res, 'الملف المطلوب غير موجود', 404);
      }
      downloadName = safeName;
    } else {
      // تصدير نسخة لحظية مباشرة من قاعدة البيانات الحالية
      const timestamp = new Date().toISOString().split('T')[0];
      downloadName = `NOCI_Attendance_Backup_${timestamp}.db`;
      const tempPath = path.join(BACKUPS_DIR, `temp_download_${Date.now()}.db`);

      db.pragma('wal_checkpoint(TRUNCATE)');
      await db.backup(tempPath);
      filePath = tempPath;
    }

    res.download(filePath, downloadName, (err) => {
      // حذف الملف المؤقت إن وجد
      if (filePath.includes('temp_download_') && fs.existsSync(filePath)) {
        try { fs.unlinkSync(filePath); } catch (_) {}
      }
    });
  } catch (err) {
    return errorResponse(res, `فشل تحميل ملف النسخة الاحتياطية: ${err.message}`, 500);
  }
}

/**
 * 4. استعادة نسخة احتياطية (من مجلد النسخ أو من ملف مرفوع)
 */
async function restoreBackup(req, res) {
  const user = req.user;
  const { filename } = req.body;
  const file = req.file;

  let targetPath = null;
  let isUploaded = false;

  try {
    if (file) {
      targetPath = file.path;
      isUploaded = true;
    } else if (filename) {
      const safeName = path.basename(filename);
      targetPath = path.join(BACKUPS_DIR, safeName);
      if (!fs.existsSync(targetPath)) {
        return errorResponse(res, 'ملف النسخة الاحتياطية المحدد غير موجود على السيرفر', 404);
      }
    } else {
      return errorResponse(res, 'يرجى تحديد ملف نسخة احتياطية للاستعادة', 400);
    }

    // التحقق من صحة ملف SQLite (Header Check)
    const fd = fs.openSync(targetPath, 'r');
    const headerBuffer = Buffer.alloc(16);
    fs.readSync(fd, headerBuffer, 0, 16, 0);
    fs.closeSync(fd);

    const headerStr = headerBuffer.toString('utf8');
    if (!headerStr.startsWith('SQLite format 3')) {
      if (isUploaded && fs.existsSync(targetPath)) fs.unlinkSync(targetPath);
      return errorResponse(res, 'الملف المرفوع ليس ملف قاعدة بيانات SQLite صالح', 400);
    }

    // Hint: التحقق من أن النسخة تخص هذا النظام (تحتوي الجداول الأساسية) وأنها سليمة
    const probe = new Database(targetPath, { readonly: true });
    let missing = [];
    let integrity = 'ok';
    try {
      const tables = new Set(probe.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all().map(t => t.name));
      missing = REQUIRED_TABLES.filter(t => !tables.has(t));
      if (missing.length === 0) integrity = probe.pragma('integrity_check', { simple: true });
    } finally {
      probe.close();
    }
    if (missing.length > 0 || integrity !== 'ok') {
      if (isUploaded && fs.existsSync(targetPath)) fs.unlinkSync(targetPath);
      return errorResponse(res, missing.length > 0
        ? `الملف ليس نسخة احتياطية لهذا النظام (جداول مفقودة: ${missing.join('، ')})`
        : 'ملف النسخة الاحتياطية تالف ولا يمكن استعادته', 400);
    }

    // 1. أخذ نسخة أمان استباقية من قاعدة البيانات الحالية قبل الاستعادة
    const { filename: safetyName } = await createBackupFile('safety_before_restore_');

    // 2. تطبيق الاستعادة في قاعدة البيانات الحالية عبر محرك SQLite دون قطع الاتصال
    const sourceDb = new Database(targetPath, { readonly: true });
    await sourceDb.backup(db.name);
    sourceDb.close();

    // Hint: ترقية بنية النسخة المستعادة إلى أحدث إصدار (ترحيلات + بذر الإعدادات الناقصة)
    db.runMigrations();
    db.seedDefaultSettings();

    // إذا كان ملف مرفوع، نحفظه في مجلد النسخ ليكون متاحاً في الأرشيف
    if (isUploaded) {
      const baseName = path.basename(file.originalname || 'upload').replace(/\.db$/i, '').replace(/[^\w\u0600-\u06FF.-]/g, '_');
      const archivedName = `restored_${Date.now()}_${baseName}.db`;
      const archivedPath = path.join(BACKUPS_DIR, archivedName);
      fs.renameSync(targetPath, archivedPath);
    }

    logAction(
      user.id,
      user.full_name,
      'استعادة نسخة احتياطية',
      `تم استعادة قاعدة البيانات بنجاح من: ${isUploaded ? file.originalname : filename} (تم حفظ نسخة أمان: ${safetyName})`
    );

    return successResponse(res, { restored: true, safetyBackup: safetyName },
      'تم استعادة قاعدة البيانات بنجاح. ملاحظة: كلمات المرور المحفوظة للكشف في نسخة من تثبيت آخر لن يمكن كشفها لاختلاف مفتاح التشفير');
  } catch (err) {
    if (isUploaded && targetPath && fs.existsSync(targetPath)) {
      try { fs.unlinkSync(targetPath); } catch (_) {}
    }
    console.error('فشل استعادة النسخة الاحتياطية:', err);
    return errorResponse(res, 'فشل عملية استعادة النسخة الاحتياطية', 500);
  }
}

/**
 * 5. حذف نسخة احتياطية محددة من السيرفر
 */
function deleteBackup(req, res) {
  const { filename } = req.params;
  const user = req.user;

  try {
    const safeName = path.basename(filename);
    const filePath = path.join(BACKUPS_DIR, safeName);

    if (!fs.existsSync(filePath)) {
      return errorResponse(res, 'الملف غير موجود', 404);
    }

    fs.unlinkSync(filePath);

    logAction(user.id, user.full_name, 'حذف نسخة احتياطية', `تم حذف النسخة الاحتياطية: ${safeName}`);

    return successResponse(res, null, 'تم حذف النسخة الاحتياطية بنجاح');
  } catch (err) {
    return errorResponse(res, `فشل حذف النسخة الاحتياطية: ${err.message}`, 500);
  }
}

module.exports = {
  listBackups,
  createBackup,
  downloadBackup,
  restoreBackup,
  deleteBackup
};
