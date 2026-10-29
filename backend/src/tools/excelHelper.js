/**
 * Hint: أداة معالجة وتحليل ملفات الإكسل (Excel Parser Helper)
 * تقرأ كشوفات البصمة وقوائم الموظفين وتنظف البيانات من الرموز والشوائب
 */
const xlsx = require('xlsx');
const { httpError } = require('../shared/responseHelper');

/**
 * تنظيف معرف الموظف (إزالة علامات الاقتباس، الفراغات، والتحويل لنص نقي)
 */
function cleanEmpCode(rawCode) {
  if (rawCode === null || rawCode === undefined) return '';
  return String(rawCode).replace(/['"`]/g, '').trim();
}

/**
 * تنظيف نصوص الأسماء والأقسام
 */
function cleanText(rawText) {
  if (!rawText) return '';
  return String(rawText).trim();
}

/**
 * Hint: قراءة ملف الموظفين الأساسي مع تحويل الخلايا الرقمية والنصية بدقة
 */
function parseMasterEmployeesFile(filePathOrBuffer) {
  const wb = readWorkbook(filePathOrBuffer);

  const sheetName = wb.SheetNames[0];
  const sheet = wb.Sheets[sheetName];
  if (!sheet) throw httpError(400, 'الملف فارغ أو لا يحتوي على صفوف بيانات');
  // Hint: استخدام raw: false لضمان تحويل كافة الحقول والأكواد إلى نصوص مقروءة
  const rawRows = xlsx.utils.sheet_to_json(sheet, { header: 1, raw: false, dateNF: 'yyyy-mm-dd hh:mm:ss' });

  if (!rawRows || rawRows.length < 2) {
    throw httpError(400, 'الملف فارغ أو لا يحتوي على صفوف بيانات');
  }

  // البحث عن أعمدة: المعرف، الاسم، القسم
  const headerRow = rawRows[0];
  let idCol = -1;
  let nameCol = -1;
  let deptCol = -1;

  for (let c = 0; c < headerRow.length; c++) {
    const val = String(headerRow[c] || '').trim();
    if (val.includes('معرف') || val.includes('المعرف') || val.includes('رقم') || val.toLowerCase().includes('id')) {
      idCol = c;
    } else if (val.includes('الاسم') || val.includes('اسم') || val.toLowerCase().includes('name')) {
      nameCol = c;
    } else if (val.includes('القسم') || val.includes('قسم') || val.toLowerCase().includes('dept')) {
      deptCol = c;
    }
  }

  // إذا لم نجدها بالأسماء، نستخدم الترتيب الافتراضي (العمود 1 المعرف، 2 الاسم، 3 القسم)
  if (idCol === -1) idCol = 1;
  if (nameCol === -1) nameCol = 2;
  if (deptCol === -1) deptCol = 3;

  const employees = [];
  for (let i = 1; i < rawRows.length; i++) {
    const r = rawRows[i];
    if (!r || r.length === 0) continue;

    const empCode = cleanEmpCode(r[idCol]);
    const name = cleanText(r[nameCol]);
    const department = cleanText(r[deptCol]) || 'عام';

    if (empCode && name) {
      // تصنيف الحالات الوظيفية الخاصة المستخرجة من عمود القسم
      let status = 'نشط';
      let isExempt = 0;
      let exemptReason = '';

      if (department.includes('استقالة')) {
        status = 'استقالة';
      } else if (department.includes('تنسيب')) {
        status = 'تنسيب';
      } else if (department.includes('متوف') || department.includes('المتوفين')) {
        status = 'متوفى';
      } else if (department.includes('الامين العام') || department.includes('الأمين العام')) {
        isExempt = 1;
        exemptReason = 'منصب قيادي (الأمين العام)';
      }

      employees.push({
        empCode,
        name,
        department,
        status,
        isExempt,
        exemptReason
      });
    }
  }

  return employees;
}

/**
 * Hint: قراءة وتحليل ملف كشف البصمة اليومي مع دعم التواريخ النصية وتواريخ Excel الرقمية (Serial Dates)
 */
// Hint: الطابع الزمني المقبول لحركة البصمة: YYYY-MM-DD HH:MM أو YYYY-MM-DD HH:MM:SS
const PUNCH_TS_RE = /^(\d{4}-\d{2}-\d{2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$/;

/**
 * Hint: توحيد الطابع الزمني إلى YYYY-MM-DD HH:MM:SS، أو null إن كان غير صالح
 */
function normalizePunchTimestamp(value) {
  const m = PUNCH_TS_RE.exec(String(value || '').trim());
  if (!m) return null;
  const [, date, hh, mm, ss = '00'] = m;
  const h = Number(hh);
  const mi = Number(mm);
  const s = Number(ss);
  if (h > 23 || mi > 59 || s > 59) return null;
  const [y, mo, d] = date.split('-').map(Number);
  const dt = new Date(Date.UTC(y, mo - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return null;
  return `${date} ${String(h).padStart(2, '0')}:${mm}:${String(s).padStart(2, '0')}`;
}

function readWorkbook(filePathOrBuffer) {
  try {
    return typeof filePathOrBuffer === 'string'
      ? xlsx.readFile(filePathOrBuffer, { cellDates: true })
      : xlsx.read(filePathOrBuffer, { type: 'buffer', cellDates: true });
  } catch (_) {
    throw httpError(400, 'تعذر قراءة الملف، تأكد أنه ملف إكسل صالح');
  }
}

/**
 * Hint: قراءة ملف البصمة وتقسيم الحركات حسب اليوم ثم حسب الموظف
 * يرجع { days: [{ date, employees }], invalidRows, totalPunchRows }
 */
function parseDailyAttendanceFile(filePathOrBuffer) {
  const wb = readWorkbook(filePathOrBuffer);

  const sheetName = wb.SheetNames[0];
  const sheet = wb.Sheets[sheetName];
  // Hint: تمرير raw: false و dateNF لضمان تنسيق خلايا الوقت الرقمية بصيغة قياسية موحدة
  const rawRows = sheet ? xlsx.utils.sheet_to_json(sheet, { header: 1, raw: false, dateNF: 'yyyy-mm-dd hh:mm:ss' }) : [];

  if (!rawRows || rawRows.length < 2) {
    throw httpError(400, 'ملف البصمة فارغ أو لا يحتوي على حركات');
  }

  // البحث عن أعمدة المعرف والاسم والقسم والوقت
  const headerRow = rawRows[0];
  let idCol = 1;
  let nameCol = 2;
  let deptCol = 3;
  let timeCol = 4;

  for (let c = 0; c < headerRow.length; c++) {
    const val = String(headerRow[c] || '').trim();
    if (val.includes('معرف') || val.includes('المعرف')) idCol = c;
    else if (val.includes('الاسم') || val.includes('اسم')) nameCol = c;
    else if (val.includes('القسم')) deptCol = c;
    else if (val.includes('الوقت') || val.includes('تاريخ') || val.toLowerCase().includes('time')) timeCol = c;
  }

  const rawPunches = [];
  let invalidRows = 0;

  for (let i = 1; i < rawRows.length; i++) {
    const r = rawRows[i];
    if (!r || r.length === 0) continue;

    const empCode = cleanEmpCode(r[idCol]);
    const name = cleanText(r[nameCol]);
    const dept = cleanText(r[deptCol]);
    const timeVal = cleanText(r[timeCol]);

    if (!empCode && !timeVal) continue;

    const timestamp = normalizePunchTimestamp(timeVal);
    if (!empCode || !timestamp) {
      invalidRows++;
      continue;
    }

    rawPunches.push({
      empCode,
      name,
      department: dept,
      date: timestamp.slice(0, 10),
      timestamp
    });
  }

  if (rawPunches.length === 0) {
    throw httpError(400, 'لم يتم العثور على حركات بصمة صالحة في الملف (الصيغة المتوقعة للوقت: YYYY-MM-DD HH:MM:SS)');
  }

  // تجميع البصمات حسب اليوم ثم حسب الموظف
  const byDate = new Map();
  for (const p of rawPunches) {
    if (!byDate.has(p.date)) byDate.set(p.date, {});
    const punchesByEmp = byDate.get(p.date);
    if (!punchesByEmp[p.empCode]) {
      punchesByEmp[p.empCode] = { empCode: p.empCode, name: p.name, department: p.department, punches: [] };
    }
    punchesByEmp[p.empCode].punches.push(p.timestamp);
  }

  const days = [...byDate.keys()].sort().map(date => ({
    date,
    employees: groupEmployeePunches(byDate.get(date))
  }));

  return {
    days,
    invalidRows,
    totalPunchRows: rawPunches.length
  };
}

/**
 * Hint: فرز حركات كل موظف وتنقية البصمات المكررة في نفس الدقيقة (Double Tap)
 */
function groupEmployeePunches(punchesByEmp) {
  const processedEmployees = [];
  for (const code of Object.keys(punchesByEmp)) {
    const item = punchesByEmp[code];
    // ترتيب البصمات زمنياً تصاعدياً
    item.punches.sort();

    // فلترة البصمات المتتالية المكررة في نفس الدقيقة (Double Tap)
    const uniquePunches = [];
    for (const punch of item.punches) {
      if (uniquePunches.length === 0) {
        uniquePunches.push(punch);
      } else {
        const last = uniquePunches[uniquePunches.length - 1];
        // إذا اختلف الوقت بأكثر من دقيقة أو كانت فارقة نضيفها
        if (punch.substring(0, 16) !== last.substring(0, 16)) {
          uniquePunches.push(punch);
        }
      }
    }

    const firstPunch = uniquePunches[0];
    const lastPunch = uniquePunches[uniquePunches.length - 1];

    processedEmployees.push({
      empCode: item.empCode,
      name: item.name,
      department: item.department,
      punchCount: uniquePunches.length,
      allPunches: uniquePunches,
      firstPunch,
      lastPunch
    });
  }

  return processedEmployees;
}

module.exports = {
  cleanEmpCode,
  cleanText,
  parseMasterEmployeesFile,
  parseDailyAttendanceFile,
  normalizePunchTimestamp
};
