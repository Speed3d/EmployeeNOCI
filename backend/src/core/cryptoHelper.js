/**
 * Hint: أداة التشفير وفك التشفير الآمن باستخدام خوارزمية AES-256-GCM
 * تستخدم لحفظ نسخة مشفرة من كلمة المرور تمكّن السوبر أدمن حصرياً من استعراضها عند الحاجة
 */
const crypto = require('crypto');
const { CIPHER_KEY } = require('./config');

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12; // الحجم القياسي الموصى به لمتجه التهيئة في GCM

/**
 * تشفير النص الصريح
 * @param {string} plainText - كلمة المرور أو النص المراد تشفيره
 * @returns {string} - النص المشفر بصيغة iv:authTag:encryptedHex
 */
function encrypt(plainText) {
  if (!plainText) return '';
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(ALGORITHM, CIPHER_KEY, iv);

  let encrypted = cipher.update(String(plainText), 'utf8', 'hex');
  encrypted += cipher.final('hex');
  const authTag = cipher.getAuthTag().toString('hex');

  return `${iv.toString('hex')}:${authTag}:${encrypted}`;
}

/**
 * فك تشفير النص المشفر (حصري للسوبر أدمن)
 * @param {string} cipherText - النص المشفر بالصيغة iv:authTag:encryptedHex
 * @returns {string} - النص الأصلي الصريح
 */
function decrypt(cipherText) {
  if (!cipherText || !cipherText.includes(':')) return '';
  try {
    const parts = cipherText.split(':');
    if (parts.length !== 3) return '';

    const iv = Buffer.from(parts[0], 'hex');
    const authTag = Buffer.from(parts[1], 'hex');
    const encryptedText = parts[2];

    const decipher = crypto.createDecipheriv(ALGORITHM, CIPHER_KEY, iv);
    decipher.setAuthTag(authTag);

    let decrypted = decipher.update(encryptedText, 'hex', 'utf8');
    decrypted += decipher.final('utf8');

    return decrypted;
  } catch (err) {
    console.error('خطأ أثناء فك التشفير:', err.message);
    return '';
  }
}

module.exports = {
  encrypt,
  decrypt
};
