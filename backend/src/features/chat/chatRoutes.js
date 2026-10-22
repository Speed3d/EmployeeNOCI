/**
 * Hint: مسارات المحادثة الفورية الداخلية
 */
const express = require('express');
const router = express.Router();
const chatController = require('./chatController');
const { authenticateToken, requireSuperAdmin } = require('../../core/authMiddleware');

router.get('/conversations', authenticateToken, chatController.listConversations);
router.get('/messages', authenticateToken, chatController.getMessages);
router.post('/messages', authenticateToken, chatController.sendMessage);
router.post('/groups', authenticateToken, requireSuperAdmin, chatController.createGroupChannel);
router.get('/unread-count', authenticateToken, chatController.getUnreadCount);

module.exports = router;
