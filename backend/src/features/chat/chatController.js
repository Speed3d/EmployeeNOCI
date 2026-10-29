/**
 * Hint: متحكم المحادثة الفورية الداخلية
 * 1. محادثات ثنائية خاصة (1-to-1) بين المستخدمين
 * 2. محادثات جماعية حصرية الإنشاء للسوبر أدمن
 * 3. وضع الرقابة الأمنية الشاملة للسوبر أدمن للاطلاع على كافة المحادثات
 */
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { ROLES } = require('../../shared/constants');
const { toPositiveInt, asTrimmedString, badRequest } = require('../../shared/validators');

const PAGE_SIZE = 150;
const MAX_MESSAGE_LENGTH = 2000;

/**
 * استعراض قائمة المحادثات (المستخدمين والمجموعات)
 * Hint: آخر رسالة وعدد غير المقروء يُجلبان باستعلامات مجمّعة بدل استعلام لكل مستخدم
 */
function listConversations(req, res) {
  const user = req.user;
  const isSuperAdmin = user.role === ROLES.SUPER_ADMIN;
  const isSurveillance = req.query.surveillance === 'true' && isSuperAdmin;

  // 1. المحادثات الخاصة مع آخر رسالة وعدد غير المقروء لكل طرف
  const users = db.prepare(`
    SELECT id, username, full_name, role, avatar_url, is_active
    FROM users
    WHERE id != ? AND deleted_at IS NULL
    ORDER BY full_name ASC
  `).all(user.id);

  const lastMessages = new Map(db.prepare(`
    SELECT CASE WHEN m.sender_id = @me THEN m.receiver_id ELSE m.sender_id END AS other_id,
           m.message, m.created_at
    FROM chat_messages m
    JOIN (
      SELECT MAX(id) AS id
      FROM chat_messages
      WHERE receiver_id IS NOT NULL AND (sender_id = @me OR receiver_id = @me)
      GROUP BY CASE WHEN sender_id = @me THEN receiver_id ELSE sender_id END
    ) last ON last.id = m.id
  `).all({ me: user.id }).map(r => [r.other_id, r]));

  const unreadCounts = new Map(db.prepare(`
    SELECT sender_id, COUNT(*) AS c
    FROM chat_messages
    WHERE receiver_id = ? AND is_read = 0
    GROUP BY sender_id
  `).all(user.id).map(r => [r.sender_id, r.c]));

  const directConversations = users.map(u => {
    const lastMsg = lastMessages.get(u.id);
    return {
      type: 'DIRECT',
      id: u.id,
      name: u.full_name,
      username: u.username,
      avatarUrl: u.avatar_url,
      role: u.role,
      lastMessage: lastMsg ? lastMsg.message : '',
      lastMessageTime: lastMsg ? lastMsg.created_at : null,
      unreadCount: unreadCounts.get(u.id) || 0
    };
  });

  // 2. المجموعات (السوبر أدمن يرى كل المجموعات، والبقية يرون مجموعاتهم فقط)
  const groups = db.prepare(`
    SELECT c.id, c.name, u.full_name AS created_by_name,
      (SELECT COUNT(*) FROM chat_members cm WHERE cm.channel_id = c.id) AS members_count,
      (SELECT m.sender_name || ': ' || m.message FROM chat_messages m WHERE m.channel_id = c.id ORDER BY m.id DESC LIMIT 1) AS last_message,
      (SELECT m.created_at FROM chat_messages m WHERE m.channel_id = c.id ORDER BY m.id DESC LIMIT 1) AS last_message_time
    FROM chat_channels c
    LEFT JOIN users u ON u.id = c.created_by
    WHERE c.is_group = 1
      AND (? = 1 OR c.id IN (SELECT channel_id FROM chat_members WHERE user_id = ?))
  `).all(isSuperAdmin ? 1 : 0, user.id).map(g => ({
    type: 'GROUP',
    id: g.id,
    name: g.name,
    createdByName: g.created_by_name,
    membersCount: g.members_count,
    lastMessage: g.last_message || '',
    lastMessageTime: g.last_message_time,
    unreadCount: 0
  }));

  // 3. سجل الرقابة للسوبر أدمن (كافة المحادثات الخاصة بين المستخدمين)
  let surveillanceConversations = [];
  if (isSurveillance) {
    surveillanceConversations = db.prepare(`
      SELECT p.user1_id, p.user2_id,
        u1.full_name AS u1_name, u1.username AS u1_username,
        u2.full_name AS u2_name, u2.username AS u2_username,
        m.sender_name, m.message, m.created_at
      FROM (
        SELECT MIN(sender_id, receiver_id) AS user1_id, MAX(sender_id, receiver_id) AS user2_id, MAX(id) AS last_id
        FROM chat_messages
        WHERE receiver_id IS NOT NULL
        GROUP BY MIN(sender_id, receiver_id), MAX(sender_id, receiver_id)
      ) p
      JOIN chat_messages m ON m.id = p.last_id
      LEFT JOIN users u1 ON u1.id = p.user1_id
      LEFT JOIN users u2 ON u2.id = p.user2_id
      ORDER BY p.last_id DESC
    `).all().map(p => ({
      type: 'SURVEILLANCE_PAIR',
      user1: { id: p.user1_id, full_name: p.u1_name, username: p.u1_username },
      user2: { id: p.user2_id, full_name: p.u2_name, username: p.u2_username },
      name: `${p.u1_name || 'مستخدم'} ↔ ${p.u2_name || 'مستخدم'}`,
      lastMessage: `${p.sender_name}: ${p.message}`,
      lastMessageTime: p.created_at
    }));
  }

  return successResponse(res, {
    direct: directConversations,
    groups,
    surveillance: surveillanceConversations
  });
}

/**
 * جلب رسائل محادثة محددة
 * Hint: بلا afterId/beforeId تُرجع أحدث 150 رسالة؛ beforeId لتحميل الأقدم، و afterId لجلب الجديد
 */
function getMessages(req, res) {
  const { type = 'DIRECT' } = req.query;
  const user = req.user;
  const targetId = toPositiveInt(req.query.targetId);
  const afterId = req.query.afterId !== undefined ? toPositiveInt(req.query.afterId) : null;
  const beforeId = req.query.beforeId !== undefined ? toPositiveInt(req.query.beforeId) : null;

  if (!targetId) {
    return badRequest(res, 'يرجى تحديد المحادثة المطلوبة');
  }

  let where;
  const params = [];

  if (type === 'GROUP') {
    // Hint: التحقق الأمني من عضوية المستخدم في المجموعة (ما لم يكن سوبر أدمن)
    if (user.role !== ROLES.SUPER_ADMIN) {
      const isMember = db.prepare('SELECT 1 FROM chat_members WHERE channel_id = ? AND user_id = ?').get(targetId, user.id);
      if (!isMember) {
        return errorResponse(res, 'غير مصرح لك بالاطلاع على رسائل هذه المجموعة', 403);
      }
    }
    where = 'channel_id = ?';
    params.push(targetId);
  } else if (type === 'SURVEILLANCE') {
    // Hint: نمط الرقابة محصور بالسوبر أدمن فقط
    const user2Id = toPositiveInt(req.query.user2Id);
    if (user.role !== ROLES.SUPER_ADMIN || !user2Id) {
      return errorResponse(res, 'غير مصرح لك بالوصول إلى سجل الرقابة الأمنية', 403);
    }
    where = '((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))';
    params.push(targetId, user2Id, user2Id, targetId);
  } else {
    where = '((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))';
    params.push(user.id, targetId, targetId, user.id);

    // تحديث حالة القراءة
    db.prepare('UPDATE chat_messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0')
      .run(targetId, user.id);
  }

  let messages;
  if (afterId) {
    messages = db.prepare(`SELECT * FROM chat_messages WHERE ${where} AND id > ? ORDER BY id ASC LIMIT ${PAGE_SIZE}`)
      .all(...params, afterId);
  } else {
    const beforeClause = beforeId ? ' AND id < ?' : '';
    messages = db.prepare(`SELECT * FROM chat_messages WHERE ${where}${beforeClause} ORDER BY id DESC LIMIT ${PAGE_SIZE}`)
      .all(...params, ...(beforeId ? [beforeId] : []))
      .reverse();
  }

  return successResponse(res, messages);
}

/**
 * إرسال رسالة في محادثة خاصة أو جماعية
 */
function sendMessage(req, res) {
  const { type = 'DIRECT' } = req.body;
  const user = req.user;
  const targetId = toPositiveInt(req.body.targetId);
  const message = typeof req.body.message === 'string' ? req.body.message.trim() : '';

  if (!message) {
    return badRequest(res, 'لا يمكن إرسال رسالة فارغة');
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    return badRequest(res, `الرسالة أطول من الحد المسموح (${MAX_MESSAGE_LENGTH} حرف)`);
  }
  if (!targetId) {
    return badRequest(res, 'يرجى تحديد المستلم أو المجموعة');
  }

  let result;

  if (type === 'GROUP') {
    const channel = db.prepare('SELECT id FROM chat_channels WHERE id = ? AND is_group = 1').get(targetId);
    if (!channel) {
      return errorResponse(res, 'المجموعة غير موجودة', 404);
    }
    // Hint: التحقق من أن المرسل عضو في المجموعة أو سوبر أدمن قبل السماح بالإرسال
    if (user.role !== ROLES.SUPER_ADMIN) {
      const isMember = db.prepare('SELECT 1 FROM chat_members WHERE channel_id = ? AND user_id = ?').get(targetId, user.id);
      if (!isMember) {
        return errorResponse(res, 'غير مصرح لك بإرسال رسائل في هذه المجموعة', 403);
      }
    }
    result = db.prepare(`
      INSERT INTO chat_messages (channel_id, sender_id, sender_name, message, is_read)
      VALUES (?, ?, ?, ?, 0)
    `).run(targetId, user.id, user.full_name, message);
  } else {
    if (targetId === user.id) {
      return badRequest(res, 'لا يمكن إرسال رسالة إلى نفسك');
    }
    const receiver = db.prepare('SELECT id FROM users WHERE id = ? AND is_active = 1 AND deleted_at IS NULL').get(targetId);
    if (!receiver) {
      return errorResponse(res, 'المستلم غير موجود أو حسابه معطل', 404);
    }
    result = db.prepare(`
      INSERT INTO chat_messages (sender_id, sender_name, receiver_id, message, is_read)
      VALUES (?, ?, ?, ?, 0)
    `).run(user.id, user.full_name, targetId, message);
  }

  const newMessage = db.prepare('SELECT * FROM chat_messages WHERE id = ?').get(result.lastInsertRowid);
  return successResponse(res, newMessage, 'تم إرسال الرسالة بنجاح', 201);
}

/**
 * إنشاء محادثة جماعية (حصري للسوبر أدمن)
 * Hint: يتم التحقق من كل الأعضاء قبل الإنشاء، والإنشاء داخل معاملة واحدة
 */
function createGroupChannel(req, res) {
  const user = req.user;
  const name = asTrimmedString(req.body.name, 100);

  if (!name) {
    return badRequest(res, 'اسم المجموعة حقل إلزامي');
  }

  const rawMembers = Array.isArray(req.body.memberIds) ? req.body.memberIds : [];
  const memberIds = [...new Set(rawMembers.map(toPositiveInt))];
  if (memberIds.some(id => id === null)) {
    return badRequest(res, 'قائمة الأعضاء تحتوي معرفات غير صالحة');
  }
  const existingCount = memberIds.length === 0 ? 0 : db.prepare(`
    SELECT COUNT(*) AS c FROM users WHERE deleted_at IS NULL AND id IN (${memberIds.map(() => '?').join(',')})
  `).get(...memberIds).c;
  if (existingCount !== memberIds.length) {
    return badRequest(res, 'بعض الأعضاء المحددين غير موجودين');
  }

  const channelId = db.transaction(() => {
    const id = db.prepare('INSERT INTO chat_channels (name, is_group, created_by) VALUES (?, 1, ?)').run(name, user.id).lastInsertRowid;
    const insertMember = db.prepare('INSERT OR IGNORE INTO chat_members (channel_id, user_id) VALUES (?, ?)');
    insertMember.run(id, user.id);
    for (const mId of memberIds) insertMember.run(id, mId);
    return id;
  })();

  logAction(user.id, user.full_name, 'إنشاء محادثة جماعية', `إنشاء مجموعة [${name}] وإضافة ${memberIds.length} أعضاء`, req.clientIp);

  return successResponse(res, { id: channelId, name }, 'تم إنشاء المحادثة الجماعية بنجاح', 201);
}

/**
 * عدد الرسائل غير المقروءة الكلي
 */
function getUnreadCount(req, res) {
  const count = db.prepare(`
    SELECT COUNT(*) as count
    FROM chat_messages
    WHERE receiver_id = ? AND is_read = 0
  `).get(req.user.id).count;

  return successResponse(res, { unreadCount: count });
}

module.exports = {
  listConversations,
  getMessages,
  sendMessage,
  createGroupChannel,
  getUnreadCount
};
