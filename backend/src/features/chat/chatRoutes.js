/**
 * Hint: مسارات المحادثة الفورية الداخلية
 */
const express = require('express');
const router = express.Router();
const chatController = require('./chatController');
const { authenticateToken } = require('../../core/authMiddleware');

router.get('/', authenticateToken, chatController.getMessages);
router.post('/', authenticateToken, chatController.sendMessage);
router.get('/unread-count', authenticateToken, chatController.getUnreadCount);

module.exports = router;
