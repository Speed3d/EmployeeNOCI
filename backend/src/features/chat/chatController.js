/**
 * Hint: متحكم المحادثة الفورية الداخلية بين مستخدمي النظام
 * يدعم التحديث اللحظي الصامت، قراءة الرسائل، وإظهار شارة الرسائل غير المقروءة
 */
const db = require('../../core/database');
const { successResponse, errorResponse } = require('../../shared/responseHelper');

function getMessages(req, res) {
  const { afterId, limit = 50 } = req.query;
  const user = req.user;

  let query = 'SELECT * FROM chat_messages WHERE 1=1';
  const params = [];

  if (afterId) {
    query += ' AND id > ?';
    params.push(afterId);
  }

  query += ' ORDER BY id ASC LIMIT ?';
  params.push(parseInt(limit, 10));

  const messages = db.prepare(query).all(...params);

  // تحديث حالة القراءة للرسائل التي لم يرسلها هذا المستخدم
  db.prepare('UPDATE chat_messages SET is_read = 1 WHERE sender_id != ? AND is_read = 0').run(user.id);

  return successResponse(res, messages);
}

function sendMessage(req, res) {
  const { message, receiverId } = req.body;
  const user = req.user;

  if (!message || !message.trim()) {
    return errorResponse(res, 'لا يمكن إرسال رسالة فارغة', 400);
  }

  const stmt = db.prepare(`
    INSERT INTO chat_messages (sender_id, sender_name, receiver_id, message, is_read)
    VALUES (?, ?, ?, ?, 0)
  `);

  const result = stmt.run(
    user.id,
    user.full_name,
    receiverId || null,
    message.trim()
  );

  const newMessage = db.prepare('SELECT * FROM chat_messages WHERE id = ?').get(result.lastInsertRowid);
  return successResponse(res, newMessage, 'تم إرسال الرسالة بنجاح', 201);
}

function getUnreadCount(req, res) {
  const user = req.user;
  const count = db.prepare(`
    SELECT COUNT(*) as count 
    FROM chat_messages 
    WHERE sender_id != ? AND is_read = 0
  `).get(user.id).count;

  return successResponse(res, { unreadCount: count });
}

module.exports = {
  getMessages,
  sendMessage,
  getUnreadCount
};
