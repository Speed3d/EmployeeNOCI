/**
 * Hint: ملف الثوابت العامة للنظام
 * يحتوي على تعريف الحالات، أدوار المستخدمين، أنواع الإجازات، وألوان البصمة
 */

// أدوار المستخدمين والصلاحيات (دوران حصرياً بناء على متطلبات النظام)
const ROLES = {
  SUPER_ADMIN: 'SUPER_ADMIN',   // Hint: سوبر أدمن - تحكم كامل، كشف كلمات المرور، تصفير، إعدادات، صيانة
  DATA_ENTRY: 'DATA_ENTRY'      // Hint: مدخل بيانات - رفع بصمة ومعاينة واعتماد، إجازات، جداول دوام، تقارير
};

// حالات البصمة اليومية للموظف
const ATTENDANCE_STATUS = {
  ON_TIME: 'ON_TIME',                   // Hint: حضور نظامي في الوقت (أخضر)
  LATE: 'LATE',                         // Hint: تأخير بسيط من 1 إلى 30 دقيقة (أصفر)
  VERY_LATE: 'VERY_LATE',               // Hint: تأخير كبير أكثر من 30 دقيقة (برتقالي)
  EARLY_LEAVE: 'EARLY_LEAVE',           // Hint: انصراف مبكر قبل الساعة 3 (أصفر أو برتقالي)
  MISSED_PUNCH: 'MISSED_PUNCH',         // Hint: بصمة واحدة فقط (لم يسجل دخول أو لم يسجل خروج)
  ABSENT: 'ABSENT',                     // Hint: غائب بدون عذر (أحمر)
  ON_LEAVE: 'ON_LEAVE',                 // Hint: مجاز رسمياً بعذر مسبق (أزرق)
  VIP_EXEMPT: 'VIP_EXEMPT',             // Hint: مستثنى إدارياً (أمين عام، مستشار)
  DEPT_EXCLUDED: 'DEPT_EXCLUDED',       // Hint: قسم مستبعد بالفلتر
  HOLIDAY: 'HOLIDAY',                   // Hint: عطلة رسمية معتمدة (أرجواني)
  OFF_DAY: 'OFF_DAY'                    // Hint: يوم راحة أسبوعي وفق جدول الدوام (رمادي مزرق)
};

// الألوان المعتمدة للحالات (Hex Codes مطابقة لنظام التصميم الملكي)
const STATUS_COLORS = {
  ON_TIME: '#178A5B',       // أخضر زمردي
  LATE: '#BE7A12',          // أصفر ذهبي / كهرماني
  VERY_LATE: '#E07A10',     // برتقالي دافئ
  ABSENT: '#C13B33',        // أحمر صريح
  ON_LEAVE: '#1E6BB8',      // أزرق هادئ
  VIP_EXEMPT: '#5A6E85',    // رمادي أنيق
  MISSED_PUNCH: '#8E44AD',  // بنفسجي هادئ
  HOLIDAY: '#7E57C2',       // أرجواني هادئ للعطلات الرسمية
  OFF_DAY: '#78909C'        // رمادي مزرق لأيام الراحة الأسبوعية
};

// أنواع الإجازات
const LEAVE_TYPES = {
  ANNUAL: 'اعتيادية',
  SICK: 'مرضية',
  HOURLY: 'زمنية (ساعية)',
  MISSION: 'إيفاد رسمي',
  EMERGENCY: 'طارئة',
  OTHER: 'أخرى'
};

module.exports = {
  ROLES,
  ATTENDANCE_STATUS,
  STATUS_COLORS,
  LEAVE_TYPES
};
