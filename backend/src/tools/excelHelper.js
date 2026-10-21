/**
 * Hint: أداة معالجة وتحليل ملفات الإكسل (Excel Parser Helper)
 * تقرأ كشوفات البصمة وقوائم الموظفين وتنظف البيانات من الرموز والشوائب
 */
const xlsx = require('xlsx');

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
 * قراءة ملف الموظفين الأساسي
 */
function parseMasterEmployeesFile(filePathOrBuffer) {
  const wb = typeof filePathOrBuffer === 'string' 
    ? xlsx.readFile(filePathOrBuffer) 
    : xlsx.read(filePathOrBuffer, { type: 'buffer' });
  
  const sheetName = wb.SheetNames[0];
  const sheet = wb.Sheets[sheetName];
  const rawRows = xlsx.utils.sheet_to_json(sheet, { header: 1 });

  if (!rawRows || rawRows.length < 2) {
    throw new Error('الملف فارغ أو لا يحتوي على صفوف بيانات');
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
 * قراءة وتحليل ملف كشف البصمة اليومي
 */
function parseDailyAttendanceFile(filePathOrBuffer) {
  const wb = typeof filePathOrBuffer === 'string' 
    ? xlsx.readFile(filePathOrBuffer) 
    : xlsx.read(filePathOrBuffer, { type: 'buffer' });
  
  const sheetName = wb.SheetNames[0];
  const sheet = wb.Sheets[sheetName];
  const rawRows = xlsx.utils.sheet_to_json(sheet, { header: 1 });

  if (!rawRows || rawRows.length < 2) {
    throw new Error('ملف البصمة فارغ أو لا يحتوي على حركات');
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
  let detectedDate = null;

  for (let i = 1; i < rawRows.length; i++) {
    const r = rawRows[i];
    if (!r || r.length === 0) continue;

    const empCode = cleanEmpCode(r[idCol]);
    const name = cleanText(r[nameCol]);
    const dept = cleanText(r[deptCol]);
    const timeVal = cleanText(r[timeCol]);

    if (empCode && timeVal) {
      // استخراج التاريخ مثل "2026-10-20" من "2026-10-20 09:18:41"
      if (!detectedDate && timeVal.includes(' ')) {
        detectedDate = timeVal.split(' ')[0];
      }

      rawPunches.push({
        empCode,
        name,
        department: dept,
        timestamp: timeVal
      });
    }
  }

  // تجميع البصمات لكل موظف وعزل البصمات المتتالية في ثوانٍ
  const punchesByEmp = {};
  for (const p of rawPunches) {
    if (!punchesByEmp[p.empCode]) {
      punchesByEmp[p.empCode] = {
        empCode: p.empCode,
        name: p.name,
        department: p.department,
        punches: []
      };
    }
    punchesByEmp[p.empCode].punches.push(p.timestamp);
  }

  // فرز وتنقية حركات كل موظف
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

    const firstPunch = item.punches[0];
    const lastPunch = item.punches[item.punches.length - 1];

    processedEmployees.push({
      empCode: item.empCode,
      name: item.name,
      department: item.department,
      punchCount: item.punches.length,
      allPunches: item.punches,
      firstPunch,
      lastPunch
    });
  }

  return {
    detectedDate,
    totalPunchRows: rawPunches.length,
    uniqueEmployeesCount: processedEmployees.length,
    employees: processedEmployees
  };
}

module.exports = {
  cleanEmpCode,
  cleanText,
  parseMasterEmployeesFile,
  parseDailyAttendanceFile
};
