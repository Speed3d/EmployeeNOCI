/**
 * Hint: أدوات الحسابات الزمنية وتحديد الدقائق والألوان والتوقيت المحلي (Asia/Baghdad)
 * مسؤولة عن حساب فوارق الوقت، التأخير، الانصراف المبكر، ومكافآت الحضور والإضافي دون انحراف المناطق الزمنية
 */

/**
 * Hint: جلب التاريخ الحالي (أو لأي كائن Date) بتوقيت بغداد بصيغة YYYY-MM-DD
 * يمنع انحراف اليوم عند تشغيل الخادم بعد منتصف الليل مقارنة بتوقيت UTC
 */
function getBaghdadDateStr(date = new Date()) {
  try {
    const formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Baghdad',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    });
    return formatter.format(date);
  } catch (_) {
    const offsetMs = 3 * 60 * 60 * 1000;
    const baghdadTime = new Date(date.getTime() + offsetMs);
    return baghdadTime.toISOString().split('T')[0];
  }
}

/**
 * Hint: استخراج رقم يوم الأسبوع (0=الأحد .. 6=السبت) من نص تاريخ YYYY-MM-DD بشكل محايد زمنياً
 */
function getDayOfWeekFromYmd(dateStr) {
  if (!dateStr) return 0;
  const parts = String(dateStr).split('T')[0].split('-').map(Number);
  if (parts.length !== 3 || parts.some(isNaN)) {
    return new Date(dateStr).getDay();
  }
  const d = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2]));
  return d.getUTCDay();
}

/**
 * Hint: إضافة أو طرح عدد أيام من تاريخ بصيغة YYYY-MM-DD وإرجاع النتيجة بنفس الصيغة دون تأثر بـ Timezone
 */
function addDaysYmd(dateStr, daysOffset) {
  const parts = String(dateStr).split('T')[0].split('-').map(Number);
  if (parts.length !== 3 || parts.some(isNaN)) {
    const d = new Date(dateStr);
    d.setDate(d.getDate() + daysOffset);
    return d.toISOString().split('T')[0];
  }
  const utcDate = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2] + daysOffset));
  return utcDate.toISOString().split('T')[0];
}

/**
 * Hint: تحويل وقت بصيغة "HH:MM" أو "HH:MM:SS" إلى دقائق منذ بداية اليوم
 */
function timeToMinutes(timeStr) {
  if (!timeStr) return null;
  const parts = String(timeStr).trim().split(':');
  if (parts.length < 2) return null;
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  if (isNaN(h) || isNaN(m)) return null;
  return h * 60 + m;
}

/**
 * Hint: فحص هل التاريخ يقع في عطلة نهاية الأسبوع (الجمعة أو السبت) بشكل محايد زمنياً
 */
function isWeekend(dateStr) {
  const day = getDayOfWeekFromYmd(dateStr);
  // 5 = Friday, 6 = Saturday
  return day === 5 || day === 6;
}

/**
 * Hint: استخراج الوقت بصيغة HH:MM:SS من نص التاريخ والوقت
 */
function extractTime(dateTimeStr) {
  if (!dateTimeStr) return '';
  const parts = String(dateTimeStr).trim().split(/\s+/);
  return parts.length > 1 ? parts[parts.length - 1] : parts[0];
}

/**
 * Hint: تنسيق الدقائق إلى نص عربي مقروء (مثال: "45 دقيقة" أو "ساعة و 15 دقيقة")
 */
function formatMinutesArabic(totalMinutes) {
  if (!totalMinutes || totalMinutes <= 0) return '0 دقيقة';
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;

  if (hours === 0) return `${minutes} دقيقة`;
  if (minutes === 0) return `${hours} ساعة`;
  return `${hours} ساعة و ${minutes} دقيقة`;
}

/**
 * Hint: حدود يوم كامل بتوقيت بغداد (UTC+3 ثابت بلا توقيت صيفي) محوّلة إلى UTC بصيغة SQLite
 * لأن CURRENT_TIMESTAMP في SQLite يُحفظ بتوقيت UTC
 * مثال: 2026-10-29 -> ['2026-10-28 21:00:00', '2026-10-29 20:59:59']
 */
function baghdadDayBoundsUtc(ymd) {
  const [y, m, d] = String(ymd).split('-').map(Number);
  const startMs = Date.UTC(y, m - 1, d, 0, 0, 0) - 3 * 60 * 60 * 1000;
  const endMs = startMs + 24 * 60 * 60 * 1000 - 1000;
  const fmt = (ms) => new Date(ms).toISOString().replace('T', ' ').slice(0, 19);
  return [fmt(startMs), fmt(endMs)];
}

module.exports = {
  baghdadDayBoundsUtc,
  getBaghdadDateStr,
  getDayOfWeekFromYmd,
  addDaysYmd,
  timeToMinutes,
  isWeekend,
  extractTime,
  formatMinutesArabic
};
