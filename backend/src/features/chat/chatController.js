/**
 * Hint: متحكم المحادثة الفورية الداخلية (الإصدار الثاني المعتمد - النقطة 11)
 * يدعم:
 * 1. محادثات ثنائية خاصة (1-to-1) بين المستخدمين
 * 2. محادثات جماعية حصرية الإنشاء للسوبر أدمن
 * 3. وضع الرقابة الأمنية الشاملة للسوبر أدمن للاطلاع على كافة المحادثات
 */
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { ROLES } = require('../../shared/constants');

/**
 * استعراض قائمة المحادثات (المستخدمين والمجموعات)
 */
function listConversations(req, res) {
  const user = req.user;
  const isSurveillance = req.query.surveillance === 'true' && user.role === ROLES.SUPER_ADMIN;

  // 1. جلب كافة المستخدمين الآخرين للمحادثات الخاصة
  const users = db.prepare(`
    SELECT id, username, full_name, role, avatar_url, is_active
    FROM users
    WHERE id != ?
    ORDER BY full_name ASC
  `).all(user.id);

  const directConversations = users.map(u => {
    // جلب آخر رسالة بين المستخدمين
    const lastMsg = db.prepare(`
      SELECT message, created_at, sender_id 
      FROM chat_messages 
      WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
      ORDER BY id DESC LIMIT 1
    `).get(user.id, u.id, u.id, user.id);

    // عدد الرسائل غير المقروءة من هذا المستخدم
    const unread = db.prepare(`
      SELECT COUNT(*) as count 
      FROM chat_messages 
      WHERE sender_id = ? AND receiver_id = ? AND is_read = 0
    `).get(u.id, user.id).count;

    return {
      type: 'DIRECT',
      id: u.id,
      name: u.full_name,
      username: u.username,
      avatarUrl: u.avatar_url,
      role: u.role,
      lastMessage: lastMsg ? lastMsg.message : '',
      lastMessageTime: lastMsg ? lastMsg.created_at : null,
      unreadCount: unread
    };
  });

  // 2. جلب المجموعات
  let groupQuery = `
    SELECT c.*, u.full_name as created_by_name
    FROM chat_channels c
    LEFT JOIN users u ON u.id = c.created_by
    WHERE c.is_group = 1
  `;
  if (!isSurveillance && user.role !== ROLES.SUPER_ADMIN) {
    groupQuery += ` AND c.id IN (SELECT channel_id FROM chat_members WHERE user_id = ${user.id})`;
  }

  const groups = db.prepare(groupQuery).all().map(g => {
    const lastMsg = db.prepare(`
      SELECT message, sender_name, created_at 
      FROM chat_messages 
      WHERE channel_id = ? 
      ORDER BY id DESC LIMIT 1
    `).get(g.id);

    const membersCount = db.prepare('SELECT COUNT(*) as c FROM chat_members WHERE channel_id = ?').get(g.id).c;

    return {
      type: 'GROUP',
      id: g.id,
      name: g.name,
      createdByName: g.created_by_name,
      membersCount,
      lastMessage: lastMsg ? `${lastMsg.sender_name}: ${lastMsg.message}` : '',
      lastMessageTime: lastMsg ? lastMsg.created_at : null,
      unreadCount: 0
    };
  });

  // 3. سجل الرقابة للسوبر أدمن (كافة المحادثات بين المستخدمين الآخرين)
  let surveillanceConversations = [];
  if (isSurveillance) {
    const pairs = db.prepare(`
      SELECT DISTINCT 
        MIN(sender_id, receiver_id) as user1_id,
        MAX(sender_id, receiver_id) as user2_id
      FROM chat_messages 
      WHERE receiver_id IS NOT NULL
    `).all();

    surveillanceConversations = pairs.map(p => {
      const u1 = db.prepare('SELECT id, full_name, username FROM users WHERE id = ?').get(p.user1_id);
      const u2 = db.prepare('SELECT id, full_name, username FROM users WHERE id = ?').get(p.user2_id);
      const lastMsg = db.prepare(`
        SELECT message, sender_name, created_at 
        FROM chat_messages 
        WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
        ORDER BY id DESC LIMIT 1
      `).get(p.user1_id, p.user2_id, p.user2_id, p.user1_id);

      return {
        type: 'SURVEILLANCE_PAIR',
        user1: u1,
        user2: u2,
        name: `${u1 ? u1.full_name : 'مستخدم'} ↔ ${u2 ? u2.full_name : 'مستخدم'}`,
        lastMessage: lastMsg ? `${lastMsg.sender_name}: ${lastMsg.message}` : '',
        lastMessageTime: lastMsg ? lastMsg.created_at : null
      };
    });
  }

  return successResponse(res, {
    direct: directConversations,
    groups,
    surveillance: surveillanceConversations
  });
}

/**
 * جلب رسائل محادثة محددة
 */
function getMessages(req, res) {
  const { type = 'DIRECT', targetId, user2Id, afterId } = req.query;
  const user = req.user;

  let query = 'SELECT * FROM chat_messages WHERE ';
  const params = [];

  if (type === 'GROUP') {
    query += 'channel_id = ?';
    params.push(targetId);
  } else if (type === 'SURVEILLANCE' && user.role === ROLES.SUPER_ADMIN && user2Id) {
    query += '((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))';
    params.push(targetId, user2Id, user2Id, targetId);
  } else {
    // محادثة ثنائية مباشرة
    query += '((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))';
    params.push(user.id, targetId, targetId, user.id);

    // تحديث حالة القراءة
    db.prepare('UPDATE chat_messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0')
      .run(targetId, user.id);
  }

  if (afterId) {
    query += ' AND id > ?';
    params.push(afterId);
  }

  query += ' ORDER BY id ASC LIMIT 150';

  const messages = db.prepare(query).all(...params);
  return successResponse(res, messages);
}

/**
 * إرسال رسالة في محادثة خاصة أو جماعية
 */
function sendMessage(req, res) {
  const { type = 'DIRECT', targetId, message } = req.body;
  const user = req.user;

  if (!message || !message.trim()) {
    return errorResponse(res, 'لا يمكن إرسال رسالة فارغة', 400);
  }

  if (!targetId) {
    return errorResponse(res, 'يرجى تحديد المستلم أو المجموعة', 400);
  }

  let stmt;
  let result;

  if (type === 'GROUP') {
    stmt = db.prepare(`
      INSERT INTO chat_messages (channel_id, sender_id, sender_name, message, is_read)
      VALUES (?, ?, ?, ?, 0)
    `);
    result = stmt.run(targetId, user.id, user.full_name, message.trim());
  } else {
    stmt = db.prepare(`
      INSERT INTO chat_messages (sender_id, sender_name, receiver_id, message, is_read)
      VALUES (?, ?, ?, ?, 0)
    `);
    result = stmt.run(user.id, user.full_name, targetId, message.trim());
  }

  const newMessage = db.prepare('SELECT * FROM chat_messages WHERE id = ?').get(result.lastInsertRowid);
  return successResponse(res, newMessage, 'تم إرسال الرسالة بنجاح', 201);
}

/**
 * إنشاء محادثة جماعية (حصري للسوبر أدمن - النقطة 11)
 */
function createGroupChannel(req, res) {
  const { name, memberIds } = req.body;
  const user = req.user;

  if (!name || !name.trim()) {
    return errorResponse(res, 'اسم المجموعة حقل إلزامي', 400);
  }

  const stmt = db.prepare('INSERT INTO chat_channels (name, is_group, created_by) VALUES (?, 1, ?)');
  const result = stmt.run(name.trim(), user.id);
  const channelId = result.lastInsertRowid;

  const insertMemberStmt = db.prepare('INSERT OR IGNORE INTO chat_members (channel_id, user_id) VALUES (?, ?)');

  // إضافة منشئ المجموعة كعضو تلقائياً
  insertMemberStmt.run(channelId, user.id);

  if (Array.isArray(memberIds)) {
    for (const mId of memberIds) {
      insertMemberStmt.run(channelId, mId);
    }
  }

  logAction(user.id, user.full_name, 'إنشاء محادثة جماعية', `إنشاء مجموعة [${name}] وإضافة ${memberIds ? memberIds.length : 0} أعضاء`);

  return successResponse(res, { id: channelId, name: name.trim() }, 'تم إنشاء المحادثة الجماعية بنجاح', 201);
}

/**
 * عدد الرسائل غير المقروءة الكلي
 */
function getUnreadCount(req, res) {
  const user = req.user;
  const count = db.prepare(`
    SELECT COUNT(*) as count 
    FROM chat_messages 
    WHERE receiver_id = ? AND is_read = 0
  `).get(user.id).count;

  return successResponse(res, { unreadCount: count });
}

module.exports = {
  listConversations,
  getMessages,
  sendMessage,
  createGroupChannel,
  getUnreadCount
};
