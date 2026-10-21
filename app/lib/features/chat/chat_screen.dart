import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';

/// Hint: شاشة المحادثة الفورية الداخلية بين مسؤولي ومستخدمي النظام
/// تطبق التحديث الصامت اللحظي كل 3 ثوانٍ دون مقاطعة الكتابة
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollingTimer;

  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _fetchMessages(initial: true);
    // بدء التحديث اللحظي الصامت كل 3 ثوانٍ
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollNewMessages();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages({bool initial = false}) async {
    if (initial) setState(() => _isLoading = true);
    try {
      final res = await ApiClient.instance.get('/chat?limit=100');
      if (mounted) {
        setState(() {
          _messages = res is List ? res : [];
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (initial && mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pollNewMessages() async {
    if (_messages.isEmpty) return;
    final lastId = _messages.last['id'];
    try {
      final res = await ApiClient.instance.get('/chat?afterId=$lastId');
      if (res is List && res.isNotEmpty && mounted) {
        setState(() {
          _messages.addAll(res);
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;

    _msgController.clear();
    setState(() => _isSending = true);

    try {
      final newMsg = await ApiClient.instance.post('/chat', {'message': text});
      if (mounted) {
        setState(() {
          _messages.add(newMsg);
          _isSending = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = AuthProvider.instance.user?['id'];
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          // شريط الترويسة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: const Row(
              children: [
                Icon(Icons.forum_rounded, color: AppColors.navy),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('غرفة المحادثة الإدارية المباشرة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('تنسيق وملاحظات فورية بين مسؤولي النظام والـ HR', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),

          // قائمة الرسائل
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('لا توجد رسائل سابقة، ابدأ المحادثة الآن'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final m = _messages[index];
                          final isMe = m['sender_id'] == myId;

                          return Align(
                            alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.7,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? AppColors.navy
                                    : (theme.brightness == Brightness.dark ? const Color(0xFF17294A) : const Color(0xFFE2E7EF)),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: isMe ? const Radius.circular(2) : const Radius.circular(14),
                                  bottomRight: isMe ? const Radius.circular(14) : const Radius.circular(2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                                children: [
                                  if (!isMe)
                                    Text(
                                      m['sender_name'] ?? 'مستخدم',
                                      style: const TextStyle(
                                        color: AppColors.goldDark,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  Text(
                                    m['message'] ?? '',
                                    style: TextStyle(
                                      color: isMe ? Colors.white : theme.textTheme.bodyMedium?.color,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTime(m['created_at']),
                                    style: TextStyle(
                                      color: isMe ? Colors.white60 : Colors.grey,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // شريط إدخال الرسالة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالتك أو ملاحظتك هنا...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.action(context),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final parts = dateStr.split(' ');
      if (parts.length > 1) {
        return parts[1].substring(0, 5);
      }
    } catch (_) {}
    return '';
  }
}
