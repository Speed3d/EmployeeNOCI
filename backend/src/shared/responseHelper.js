/**
 * Hint: مساعد توحيد الردود البرمجية للـ API
 * يضمن وصول كل استجابة للفرونت إند (ويب أو موبايل) بصيغة موحدة وسلسة
 */

function successResponse(res, data = null, message = 'تمت العملية بنجاح', statusCode = 200) {
  return res.status(statusCode).json({
    success: true,
    message,
    data,
    timestamp: new Date().toISOString()
  });
}

function errorResponse(res, message = 'حدث خطأ في معالجة الطلب', statusCode = 400, errors = null) {
  return res.status(statusCode).json({
    success: false,
    message,
    errors,
    timestamp: new Date().toISOString()
  });
}

module.exports = {
  successResponse,
  errorResponse
};
