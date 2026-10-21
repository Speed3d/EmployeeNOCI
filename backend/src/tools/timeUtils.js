/**
 * Hint: أدوات الحسابات الزمنية وتحديد الدقائق والألوان
 * مسؤولة عن حساب فوارق الوقت، التأخير، الانصراف المبكر، ومكافآت الحضور والإضافي
 */

/**
 * تحويل وقت بصيغة "HH:MM" أو "HH:MM:SS" إلى دقائق منذ بداية اليوم
 */
function timeToMinutes(timeStr) {
  if (!timeStr) return null;
  const parts = timeStr.trim().split(':');
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  return h * 60 + m;
}

/**
 * فحص هل التاريخ يقع في عطلة نهاية الأسبوع (الجمعة أو السبت)
 */
function isWeekend(dateStr) {
  const d = new Date(dateStr);
  const day = d.getDay();
  // 5 = Friday, 6 = Saturday
  return day === 5 || day === 6;
}

/**
 * استخراج الوقت بصيغة HH:MM:SS من نص التاريخ والوقت
 */
function extractTime(dateTimeStr) {
  if (!dateTimeStr) return '';
  const parts = dateTimeStr.trim().split(' ');
  return parts.length > 1 ? parts[1] : parts[0];
}

/**
 * تنسيق الدقائق إلى نص عربي مقروء (مثال: "45 دقيقة" أو "ساعة و 15 دقيقة")
 */
function formatMinutesArabic(totalMinutes) {
  if (!totalMinutes || totalMinutes <= 0) return '0 دقيقة';
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;

  if (hours === 0) return `${minutes} دقيقة`;
  if (minutes === 0) return `${hours} ساعة`;
  return `${hours} ساعة و ${minutes} دقيقة`;
}

module.exports = {
  timeToMinutes,
  isWeekend,
  extractTime,
  formatMinutesArabic
};
