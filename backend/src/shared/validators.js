/**
 * Hint: أدوات التحقق الموحدة من مدخلات الطلبات
 * تمنع وصول قيم من نوع غير متوقع أو بصيغة خاطئة إلى قاعدة البيانات أو محرك الحضور
 */
const { errorResponse } = require('./responseHelper');

// Hint: تاريخ بصيغة YYYY-MM-DD ويجب أن يكون تاريخاً حقيقياً (يرفض 2026-02-30)
function isYmd(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d;
}

// Hint: وقت بصيغة HH:MM ضمن اليوم الواحد
function isHHMM(value) {
  if (typeof value !== 'string' || !/^\d{2}:\d{2}$/.test(value)) return false;
  const [h, m] = value.split(':').map(Number);
  return h >= 0 && h <= 23 && m >= 0 && m <= 59;
}

// Hint: عدد صحيح موجب أو null إن لم يكن صالحاً
function toPositiveInt(value) {
  if (value === null || value === undefined || value === '') return null;
  const n = typeof value === 'number' ? value : Number(String(value).trim());
  return Number.isInteger(n) && n > 0 ? n : null;
}

// Hint: نص منظف بطول أقصى، أو null إن لم يكن نصاً
function asTrimmedString(value, maxLen = 255) {
  if (typeof value === 'number') value = String(value);
  if (typeof value !== 'string') return null;
  const s = value.trim();
  return s.length <= maxLen ? s : null;
}

// Hint: قيمة منطقية صارمة؛ تقبل true/1/"true"/"1" فقط كصحيح
function asBool(value) {
  return value === true || value === 1 || value === 'true' || value === '1';
}

function isHexColor(value) {
  return typeof value === 'string' && /^#[0-9A-Fa-f]{6}$/.test(value);
}

// Hint: أيام العمل كمصفوفة أعداد صحيحة 0..6 بلا تكرار
function isWorkDaysArray(value) {
  return Array.isArray(value)
    && value.every(d => Number.isInteger(d) && d >= 0 && d <= 6)
    && new Set(value).size === value.length;
}

// Hint: سياسة كلمات المرور: 8 خانات على الأقل وتحتوي حرفاً ورقماً، بلا مسافات في الأطراف
function passwordPolicyError(password) {
  if (typeof password !== 'string') return 'كلمة المرور غير صالحة';
  if (password !== password.trim()) return 'لا يُسمح بمسافات في بداية أو نهاية كلمة المرور';
  if (password.length < 8) return 'يجب ألا تقل كلمة المرور عن 8 خانات';
  if (!/[A-Za-z؀-ۿ]/.test(password) || !/[0-9٠-٩]/.test(password)) {
    return 'يجب أن تحتوي كلمة المرور على حرف ورقم على الأقل';
  }
  return null;
}

function badRequest(res, message) {
  return errorResponse(res, message, 400);
}

module.exports = {
  isYmd,
  isHHMM,
  toPositiveInt,
  asTrimmedString,
  asBool,
  isHexColor,
  isWorkDaysArray,
  passwordPolicyError,
  badRequest
};
