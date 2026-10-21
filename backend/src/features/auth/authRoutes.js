/**
 * Hint: مسارات المصادقة والمستخدمين
 */
const express = require('express');
const router = express.Router();
const authController = require('./authController');
const { authenticateToken } = require('../../core/authMiddleware');

router.post('/login', authController.login);
router.get('/me', authenticateToken, authController.getMe);
router.post('/change-password', authenticateToken, authController.changePassword);

module.exports = router;
