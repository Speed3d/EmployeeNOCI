import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../tools/date_formatter.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';

/// Hint: شاشة المحادثة الفورية الداخلية (الإصدار الثاني المعتمد - النقطة 11)
/// تدعم: المحادثات الثنائية الخاصة، المجموعات، ووضع الرقابة الأمنية الشاملة للسوبر أدمن
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollingTimer;

  bool _isLoadingConversations = true;
  bool _isLoadingMessages = false;
  bool _isSending = false;

  List<dynamic> _directConversations = [];
  List<dynamic> _groups = [];
  List<dynamic> _surveillancePairs = [];

  bool _isSurveillanceExpanded = false;
  bool _isSurveillanceUnlocked = false;

  String _currentType = 'DIRECT'; // DIRECT, GROUP, SURVEILLANCE
  int? _currentTargetId;
  int? _surveillanceUser2Id;
  String _activeTitle = 'اختر محادثة للبدء';

  List<dynamic> _messages = [];
  static const int _pageSize = 150;
  bool _hasOlder = false;
  bool _isLoadingOlder = false;

  @override
  void initState() {
    super.initState();
    _loadConversations(initial: true);

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _pollActiveConversation();
      // Hint: تحديث قائمة المحادثات والعدادات كل 6 ثوانٍ لضمان ظهور المجموعات والرسائل الجديدة فوراً
      if (timer.tick % 2 == 0) {
        _loadConversations();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations({bool initial = false}) async {
    if (initial) setState(() => _isLoadingConversations = true);
    try {
      final isSuper = AuthProvider.instance.isSuperAdmin;
      final res = await ApiClient.instance.get('/chat/conversations?surveillance=$isSuper');

      if (mounted) {
        setState(() {
          _directConversations = res['direct'] ?? [];
          _groups = res['groups'] ?? [];
          _surveillancePairs = res['surveillance'] ?? [];
          _isLoadingConversations = false;
        });

        // إذا لم تكن هناك محادثة نشطة، نفتح أول محادثة خاصة تلقائياً
        if (_currentTargetId == null && _directConversations.isNotEmpty) {
          final first = _directConversations.first;
          _selectConversation('DIRECT', first['id'], first['name']);
        }
      }
    } catch (_) {
      if (mounted && initial) setState(() => _isLoadingConversations = false);
    }
  }

  void _selectConversation(String type, int targetId, String title, {int? user2Id}) {
    setState(() {
      _currentType = type;
      _currentTargetId = targetId;
      _surveillanceUser2Id = user2Id;
      _activeTitle = title;
      _messages.clear();
      _isLoadingMessages = true;
    });

    _loadMessages();
  }

  Future<void> _loadMessages() async {
    if (_currentTargetId == null) return;
    try {
      String url = '/chat/messages?type=$_currentType&targetId=$_currentTargetId';
      if (_currentType == 'SURVEILLANCE' && _surveillanceUser2Id != null) {
        url += '&user2Id=$_surveillanceUser2Id';
      }

      final res = await ApiClient.instance.get(url);
      if (mounted) {
        setState(() {
          _messages = res is List ? res : [];
          // Hint: الخادم يرجع أحدث 150 رسالة؛ إذا اكتملت الصفحة فقد توجد رسائل أقدم
          _hasOlder = _messages.length >= _pageSize;
          _isLoadingMessages = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMessages = false);
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_currentTargetId == null || _messages.isEmpty || _isLoadingOlder) return;
    setState(() => _isLoadingOlder = true);
    try {
      String url = '/chat/messages?type=$_currentType&targetId=$_currentTargetId&beforeId=${_messages.first['id']}';
      if (_currentType == 'SURVEILLANCE' && _surveillanceUser2Id != null) {
        url += '&user2Id=$_surveillanceUser2Id';
      }
      final res = await ApiClient.instance.get(url);
      if (!mounted) return;
      final older = res is List ? res : [];
      setState(() {
        _messages.insertAll(0, older);
        _hasOlder = older.length >= _pageSize;
        _isLoadingOlder = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingOlder = false);
    }
  }

  // Hint: إضافة رسائل جديدة دون تكرار (قد تصل نفس الرسالة من الإرسال ومن الاستطلاع الدوري)
  void _appendMessages(List<dynamic> incoming) {
    final known = _messages.map((m) => m['id']).toSet();
    final fresh = incoming.where((m) => !known.contains(m['id'])).toList();
    if (fresh.isEmpty) return;
    if (!mounted) return;
    setState(() => _messages.addAll(fresh));
    _scrollToBottom();
  }

  Future<void> _pollActiveConversation() async {
    if (_currentTargetId == null) return;

    final lastId = _messages.isNotEmpty ? _messages.last['id'] : null;
    try {
      String url = '/chat/messages?type=$_currentType&targetId=$_currentTargetId';
      if (_currentType == 'SURVEILLANCE' && _surveillanceUser2Id != null) {
        url += '&user2Id=$_surveillanceUser2Id';
      }
      if (lastId != null) {
        url += '&afterId=$lastId';
      }

      final res = await ApiClient.instance.get(url);
      if (res is List && res.isNotEmpty && mounted) {
        _appendMessages(res);
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending || _currentTargetId == null) return;

    _msgController.clear();
    setState(() => _isSending = true);

    try {
      final res = await ApiClient.instance.post('/chat/messages', {
        'type': _currentType,
        'targetId': _currentTargetId,
        'message': text,
      });

      if (mounted) {
        setState(() => _isSending = false);
        _appendMessages([res]);
        _loadConversations();
      }
    } catch (e) {
      if (!mounted) return;
      // Hint: إرجاع نص الرسالة عند الفشل حتى لا يضيع ما كتبه المستخدم
      _msgController.text = text;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('تعذر إرسال الرسالة: $e')),
      );
    }
  }

  /// Hint: طي / توسيع سجل الرقابة الأمنية الشاملة مع التحقق الأمني بكلمة مرور السوبر أدمن
  Future<void> _toggleSurveillance() async {
    if (_isSurveillanceExpanded) {
      setState(() {
        _isSurveillanceExpanded = false;
      });
      return;
    }

    if (_isSurveillanceUnlocked) {
      setState(() {
        _isSurveillanceExpanded = true;
      });
      return;
    }

    // طلب كلمة مرور السوبر أدمن للتأكيد الأمني
    final bool? verified = await _showPasswordPromptDialog();
    if (verified == true && mounted) {
      setState(() {
        _isSurveillanceUnlocked = true;
        _isSurveillanceExpanded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.lock_open_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('تم التحقق بنجاح وفتح سجل الرقابة الشاملة'),
            ],
          ),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// حوار إدخال وتأكيد كلمة مرور السوبر أدمن
  Future<bool?> _showPasswordPromptDialog() async {
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    bool isVerifying = false;
    String? errorMsg;

    String cleanDigits(String s) {
      const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
      for (int i = 0; i < 10; i++) {
        s = s.replaceAll(ar[i], '$i');
      }
      return s.trim();
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.security_rounded, color: AppColors.danger),
                SizedBox(width: 8),
                Text('تأكيد أمني مطلوب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'عرض سجل الرقابة الشاملة على محادثات الموظفين مخصص للسوبر أدمن ويتطلب إدخال كلمة المرور للتأكيد:',
                    style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: obscure,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'كلمة مرور السوبر أدمن',
                        hintText: 'أدخل كلمة مرور الحساب الحالية',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                          onPressed: () => setDlgState(() => obscure = !obscure),
                        ),
                        errorText: errorMsg,
                      ),
                    onSubmitted: (_) async {
                      if (isVerifying) return;
                      final pwd = cleanDigits(passwordCtrl.text);
                      if (pwd.isEmpty) {
                        setDlgState(() => errorMsg = 'يرجى إدخال كلمة المرور');
                        return;
                      }
                      setDlgState(() {
                        isVerifying = true;
                        errorMsg = null;
                      });
                      try {
                        await ApiClient.instance.post('/auth/verify-password', {'password': pwd});
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (!context.mounted) return;
                        setDlgState(() {
                          isVerifying = false;
                          errorMsg = 'كلمة المرور غير صحيحة، يرجى المحاولة ثانية';
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isVerifying ? null : () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: isVerifying
                    ? null
                    : () async {
                        final pwd = cleanDigits(passwordCtrl.text);
                        if (pwd.isEmpty) {
                          setDlgState(() => errorMsg = 'يرجى إدخال كلمة المرور');
                          return;
                        }
                        setDlgState(() {
                          isVerifying = true;
                          errorMsg = null;
                        });
                        try {
                          await ApiClient.instance.post('/auth/verify-password', {'password': pwd});
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (e) {
                          if (!context.mounted) return;
                          setDlgState(() {
                            isVerifying = false;
                            errorMsg = 'كلمة المرور غير صحيحة، يرجى المحاولة ثانية';
                          });
                        }
                      },
                icon: isVerifying
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.lock_open_rounded, size: 16),
                label: const Text('تأكيد وفتح'),
              ),
            ],
          );
        },
      ),
    );
  }

  // إنشاء محادثة جماعية جديدة (حصري للسوبر أدمن)
  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    final Set<int> selectedUserIds = {};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.group_add_rounded, color: AppColors.navy),
                SizedBox(width: 8),
                Text('إنشاء محادثة جماعية جديدة'),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المجموعة *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('حدد أعضاء المجموعة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      itemCount: _directConversations.length,
                      itemBuilder: (context, index) {
                        final u = _directConversations[index];
                        final uId = u['id'] as int;
                        final isChecked = selectedUserIds.contains(uId);

                        return CheckboxListTile(
                          dense: true,
                          title: Text(u['name'], style: const TextStyle(fontSize: 13)),
                          subtitle: Text('@${u['username']}', style: const TextStyle(fontSize: 11)),
                          value: isChecked,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedUserIds.add(uId);
                              } else {
                                selectedUserIds.remove(uId);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                onPressed: () async {
                  final groupName = nameController.text.trim();
                  if (groupName.isEmpty) return;

                  final navigator = Navigator.of(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ApiClient.instance.post('/chat/groups', {
                      'name': groupName,
                      'memberIds': selectedUserIds.toList(),
                    });
                    navigator.pop();
                    _loadConversations();
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('خطأ: $e')));
                  }
                },
                child: const Text('إنشاء المجموعة'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.instance;
    final isSuper = auth.isSuperAdmin;

    return Scaffold(
      body: Row(
        children: [
          // 1. القائمة الجانبية للمحادثات
          Container(
            width: 320,
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color ?? Colors.white,
              border: Border(left: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
            ),
            child: Column(
              children: [
                // رأس القائمة الجانبية
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Text(
                        'المحادثات',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Spacer(),
                      if (isSuper)
                        IconButton(
                          icon: const Icon(Icons.group_add_rounded, color: AppColors.navy),
                          tooltip: 'إنشاء محادثة جماعية',
                          onPressed: _showCreateGroupDialog,
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // قائمة المحادثات (خاصة، مجموعات، ورقابة)
                Expanded(
                  child: _isLoadingConversations
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          children: [
                            // قسم المجموعات
                            if (_groups.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                                child: Text('مجموعات العمل (${_groups.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                              ),
                              for (final g in _groups)
                                ListTile(
                                  dense: true,
                                  selected: _currentType == 'GROUP' && _currentTargetId == g['id'],
                                  selectedTileColor: AppColors.navy.withValues(alpha: 0.08),
                                  leading: const CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppColors.gold,
                                    child: Icon(Icons.groups_rounded, size: 18, color: Colors.white),
                                  ),
                                  title: Text(g['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  subtitle: Text(g['lastMessage'] ?? 'لا توجد رسائل', style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onTap: () => _selectConversation('GROUP', g['id'], g['name']),
                                ),
                            ],

                            // قسم المحادثات الخاصة
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                              child: Text('المحادثات الخاصة (${_directConversations.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                            ),
                            for (final u in _directConversations)
                              ListTile(
                                dense: true,
                                selected: _currentType == 'DIRECT' && _currentTargetId == u['id'],
                                selectedTileColor: AppColors.navy.withValues(alpha: 0.08),
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.navy.withValues(alpha: 0.12),
                                  child: Text(
                                    (u['name'] ?? 'U').substring(0, 1),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy, fontSize: 12),
                                  ),
                                ),
                                title: Text(u['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text(u['lastMessage'] ?? 'انقر للبدء', style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: (u['unreadCount'] ?? 0) > 0
                                    ? CircleAvatar(
                                        radius: 10,
                                        backgroundColor: AppColors.danger,
                                        child: Text('${u['unreadCount']}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                      )
                                    : null,
                                onTap: () => _selectConversation('DIRECT', u['id'], u['name']),
                              ),

                            // قسم الرقابة الأمنية الشاملة (للسوبر أدمن فقط - قابل للطي مع قفل أمني)
                            if (isSuper) ...[
                              const Divider(height: 24),
                              InkWell(
                                onTap: _toggleSurveillance,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _isSurveillanceExpanded
                                        ? AppColors.danger.withValues(alpha: 0.08)
                                        : Colors.grey.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _isSurveillanceExpanded
                                          ? AppColors.danger.withValues(alpha: 0.2)
                                          : Colors.grey.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _isSurveillanceUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                                        size: 16,
                                        color: AppColors.danger,
                                      ),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'سجل الرقابة الشاملة (سوبر أدمن)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: AppColors.danger,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        _isSurveillanceExpanded
                                            ? Icons.keyboard_arrow_up_rounded
                                            : Icons.keyboard_arrow_down_rounded,
                                        size: 20,
                                        color: AppColors.danger,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_isSurveillanceExpanded && _isSurveillanceUnlocked) ...[
                                const SizedBox(height: 6),
                                if (_surveillancePairs.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    child: Text(
                                      'لا توجد محادثات ثنائية بين الموظفين حتى الآن',
                                      style: TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  )
                                else
                                  for (final p in _surveillancePairs)
                                    ListTile(
                                      dense: true,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      selected: _currentType == 'SURVEILLANCE' &&
                                          _currentTargetId == p['user1']['id'] &&
                                          _surveillanceUser2Id == p['user2']['id'],
                                      selectedTileColor: AppColors.danger.withValues(alpha: 0.08),
                                      leading: const Icon(Icons.remove_red_eye_rounded, size: 18, color: AppColors.late),
                                      title: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      subtitle: Text(p['lastMessage'] ?? '', style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      onTap: () => _selectConversation(
                                        'SURVEILLANCE',
                                        p['user1']['id'],
                                        'رقابة: ${p['name']}',
                                        user2Id: p['user2']['id'],
                                      ),
                                    ),
                              ],
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),

          // 2. منطقة عرض الرسائل والإرسال
          Expanded(
            child: Column(
              children: [
                // رأس المحادثة النشطة
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color ?? Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _currentType == 'GROUP'
                            ? Icons.groups_rounded
                            : _currentType == 'SURVEILLANCE'
                                ? Icons.security_rounded
                                : Icons.person_rounded,
                        color: _currentType == 'SURVEILLANCE' ? AppColors.danger : AppColors.navy,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _activeTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),

                // قائمة الرسائل
                Expanded(
                  child: _isLoadingMessages
                      ? const Center(child: CircularProgressIndicator())
                      : _messages.isEmpty
                          ? const Center(child: Text('لا توجد رسائل سابقة في هذه المحادثة'))
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _messages.length + (_hasOlder ? 1 : 0),
                              itemBuilder: (context, rawIndex) {
                                if (_hasOlder && rawIndex == 0) {
                                  return Center(
                                    child: TextButton.icon(
                                      onPressed: _isLoadingOlder ? null : _loadOlderMessages,
                                      icon: _isLoadingOlder
                                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Icon(Icons.history_rounded, size: 16),
                                      label: const Text('تحميل رسائل أقدم'),
                                    ),
                                  );
                                }
                                final index = _hasOlder ? rawIndex - 1 : rawIndex;
                                final msg = _messages[index];
                                final isMe = msg['sender_id'] == auth.user?['id'];

                                return Align(
                                  alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    constraints: const BoxConstraints(maxWidth: 550),
                                    decoration: BoxDecoration(
                                      color: isMe ? AppColors.navy : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                                      children: [
                                        if (!isMe)
                                          Text(
                                            msg['sender_name'] ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.navy),
                                          ),
                                        Text(
                                          msg['message'] ?? '',
                                          style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 13),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          DateFormatter.dbTimestampToLocal(msg['created_at']).split(' ').skip(1).join(' '),
                                          style: TextStyle(color: isMe ? Colors.white70 : Colors.grey, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),

                // شريط إدخال الرسالة (يُخفى في وضع المراقبة)
                if (_currentType != 'SURVEILLANCE')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color ?? Colors.white,
                      border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _msgController,
                            decoration: InputDecoration(
                              hintText: 'اكتب رسالتك هنا...',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send_rounded, color: AppColors.navy),
                          onPressed: _sendMessage,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
