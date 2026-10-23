import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import 'employee_dialog.dart';

/// Hint: شاشة إدارة سجلات الموظفين ودليل المقر ونقل الموظفين (النقطة 16)
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _employees = [];
  List<dynamic> _departments = [];
  String _searchQuery = '';
  String? _selectedDept;

  // ألوان تمييز حالات الموظفين القابلة للتخصيص من الإعدادات
  Color _colorActiveLeave = const Color(0xFFE3F2FD); // أزرق فاتح
  Color _colorSeconded = const Color(0xFFFFE0B2);    // برتقالي فاتح واضح (تنسيب)
  Color _colorTerminated = const Color(0xFFFFCDD2);  // أحمر فاتح واضح
  Color _colorVipExempt = const Color(0xFFECEFF1);   // رمادي فاتح

  static Color parseHex(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    try {
      String clean = hex.replaceAll('#', '').trim();
      if (clean.length == 6) clean = 'FF$clean';
      return Color(int.parse(clean, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadDepartments();
    _loadEmployees();
  }

  Future<void> _loadSettings() async {
    try {
      final res = await ApiClient.instance.get('/settings');
      if (res is Map && mounted) {
        setState(() {
          _colorActiveLeave = parseHex(res['color_active_leave'], const Color(0xFFE8F1FC));
          _colorSeconded = parseHex(res['color_seconded'], const Color(0xFFFFF3E0));
          _colorTerminated = parseHex(res['color_terminated'], const Color(0xFFFFEBEE));
          _colorVipExempt = parseHex(res['color_vip_exempt'], const Color(0xFFECEFF1));
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDepartments() async {
    try {
      final res = await ApiClient.instance.get('/employees/departments');
      if (res is List) {
        setState(() {
          _departments = res;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String url = '/employees?';
      if (_searchQuery.isNotEmpty) {
        url += 'search=${Uri.encodeComponent(_searchQuery)}&';
      }
      if (_selectedDept != null && _selectedDept!.isNotEmpty) {
        url += 'department=${Uri.encodeComponent(_selectedDept!)}&';
      }

      final res = await ApiClient.instance.get(url);
      setState(() {
        _employees = res is List ? res : [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // نقل الموظف بين الأقسام مع الأرشفة (النقطة 16)
  void _showTransferDialog(Map<String, dynamic> emp) {
    String? targetDept = _departments.isNotEmpty ? _departments.first['name'].toString() : '';
    final reasonController = TextEditingController();

    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.swap_horiz_rounded, color: AppColors.navy),
                const SizedBox(width: 8),
                Text('نقل الموظف: ${emp['name']}'),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'القسم الحالي: ${emp['department']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  const Text('القسم الجديد المراد النقل إليه:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: targetDept,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: _departments.map((d) {
                      final name = d['name'].toString();
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (val) => setDialogState(() => targetDept = val),
                  ),
                  const SizedBox(height: 14),
                  const Text('سبب أو أمر النقل الإداري:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      hintText: 'مثال: أمر إداري رقم 123 لسنة 2026...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                onPressed: targetDept == null || targetDept == emp['department']
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        setState(() => _isLoading = true);
                        try {
                          await ApiClient.instance.post('/employees/${emp['id']}/transfer', {
                            'newDepartment': targetDept,
                            'reason': reasonController.text.trim(),
                          });
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.onTime,
                              content: Text('تم نقل الموظف إلى قسم [$targetDept] بنجاح وتسجيل النقل في السجل!'),
                            ),
                          );
                          _loadEmployees();
                        } catch (e) {
                          if (!mounted) return;
                          setState(() => _isLoading = false);
                          messenger.showSnackBar(
                            SnackBar(backgroundColor: AppColors.danger, content: Text('فشل النقل: $e')),
                          );
                        }
                      },
                child: const Text('تأكيد النقل'),
              ),
            ],
          );
        },
      ),
    );
  }

  // استيراد الموظفين من ملف الإكسل الأساسي
  Future<void> _importMasterEmployees() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.xFile.readAsBytes();

        setState(() => _isLoading = true);
        final res = await ApiClient.instance.uploadFile('/employees/import-excel', bytes, file.name);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.onTime,
            content: Text(res['message'] ?? 'تم استيراد الموظفين بنجاح!'),
          ),
        );
        _loadDepartments();
        _loadEmployees();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('فشل الاستيراد: $e')),
      );
    }
  }

  void _showEmployeeDialog([Map<String, dynamic>? employee]) {
    showDialog(
      context: context,
      builder: (ctx) => EmployeeDialog(
        employee: employee,
        onSaved: () {
          _loadDepartments();
          _loadEmployees();
        },
      ),
    );
  }

  Future<void> _deleteEmployee(Map<String, dynamic> emp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الموظف'),
        content: Text('هل أنت متأكد من حذف الموظف [${emp['emp_code']}] ${emp['name']}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiClient.instance.delete('/employees/${emp['id']}');
        _loadEmployees();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // عرض الملف الشخصي الكامل للموظف (سجل الإجازات والأذونات، التنقلات، والحضور)
  Future<void> _showEmployeeProfileDialog(Map<String, dynamic> emp) async {
    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return FutureBuilder<dynamic>(
            future: ApiClient.instance.get('/employees/${emp['id']}'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AlertDialog(
                  content: SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }

              if (snapshot.hasError || snapshot.data == null) {
                return AlertDialog(
                  title: const Text('خطأ'),
                  content: Text('فشل تحميل تفاصيل الموظف: ${snapshot.error}'),
                  actions: [TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('إغلاق'))],
                );
              }

              final data = snapshot.data;
              final fullEmp = data['employee'] ?? emp;
              final List<dynamic> leaves = data['leaves'] ?? [];
              final List<dynamic> transfers = data['transfers'] ?? [];
              final List<dynamic> attendance = data['recentAttendance'] ?? [];

              final bool hasActiveLeave = emp['has_active_leave'] == 1;
              final String status = (fullEmp['status'] ?? '').toString();

              return DefaultTabController(
                length: 3,
                child: AlertDialog(
                  titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.navy,
                        child: Text(
                          '${fullEmp['emp_code']}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullEmp['name'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              '${fullEmp['department']} • الحالة: $status',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: 650,
                    height: 480,
                    child: Column(
                      children: [
                        if (hasActiveLeave)
                          Container(
                            margin: const EdgeInsets.only(top: 8, bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F2FD),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF90CAF9)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.beach_access_rounded, color: AppColors.info, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'الموظف حالياً في إجازة رسمية: (${emp['active_leave_type'] ?? 'إجازة معتمدة'})',
                                    style: const TextStyle(color: AppColors.info, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const TabBar(
                          labelColor: AppColors.navy,
                          indicatorColor: AppColors.gold,
                          tabs: [
                            Tab(icon: Icon(Icons.beach_access_rounded, size: 18), text: 'سجل الإجازات'),
                            Tab(icon: Icon(Icons.swap_horiz_rounded, size: 18), text: 'سجل التنقلات'),
                            Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'آخر حركات الحضور'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              // 1. سجل الإجازات والأذونات
                              leaves.isEmpty
                                  ? const Center(child: Text('لا توجد إجازات مسجلة لهذا الموظف', style: TextStyle(color: Colors.grey)))
                                  : ListView.separated(
                                      padding: const EdgeInsets.only(top: 12),
                                      itemCount: leaves.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (ctx, i) {
                                        final l = leaves[i];
                                        return ListTile(
                                          dense: true,
                                          leading: const Icon(Icons.event_available_rounded, color: AppColors.info, size: 20),
                                          title: Text(
                                            '${l['leave_type']} (من ${l['start_date']} إلى ${l['end_date']})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          subtitle: Text(
                                            (l['reason'] != null && l['reason'].toString().isNotEmpty ? 'السبب: ${l['reason']}' : 'بدون ملاحظات') +
                                                (l['created_at'] != null ? ' • تاريخ التسجيل: ${l['created_at'].toString().split(' ')[0]}' : ''),
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                        );
                                      },
                                    ),
                              // 2. سجل التنقلات الإدارية
                              transfers.isEmpty
                                  ? const Center(child: Text('لا توجد تنقلات مسجلة لهذا الموظف', style: TextStyle(color: Colors.grey)))
                                  : ListView.separated(
                                      padding: const EdgeInsets.only(top: 12),
                                      itemCount: transfers.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (ctx, i) {
                                        final t = transfers[i];
                                        return ListTile(
                                          dense: true,
                                          leading: const Icon(Icons.swap_horiz_rounded, color: AppColors.navy, size: 20),
                                          title: Text(
                                            'من [${t['previous_department']}] ⬅️ إلى [${t['new_department']}]',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          subtitle: Text(
                                            (t['reason'] != null ? 'الأمر/السبب: ${t['reason']}' : '') +
                                                (t['created_at'] != null ? ' • بتاريخ: ${t['created_at'].toString().split(' ')[0]}' : ''),
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                        );
                                      },
                                    ),
                              // 3. آخر حركات الحضور
                              attendance.isEmpty
                                  ? const Center(child: Text('لا توجد حركات حضور مسجلة', style: TextStyle(color: Colors.grey)))
                                  : ListView.separated(
                                      padding: const EdgeInsets.only(top: 12),
                                      itemCount: attendance.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (ctx, i) {
                                        final a = attendance[i];
                                        return ListTile(
                                          dense: true,
                                          leading: const Icon(Icons.access_time_filled_rounded, color: AppColors.onTime, size: 18),
                                          title: Text(
                                            'التاريخ: ${a['date']} • الحالة: ${a['status']}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                          subtitle: Text(
                                            'دخول: ${a['check_in_time'] ?? '--:--'} • خروج: ${a['check_out_time'] ?? '--:--'} • تأخير: ${a['delay_minutes'] ?? 0} دقيقة',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                        );
                                      },
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('إغلاق')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.instance;

    return Scaffold(
      body: Column(
        children: [
          // شريط الأدوات العلوي
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color ?? Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.15))),
            ),
            child: Row(
              children: [
                // مربع البحث
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم، المعرف، أو الهاتف...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) {
                        _searchQuery = val;
                        _loadEmployees();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // فلتر القسم
                SizedBox(
                  width: 220,
                  height: 40,
                  child: DropdownButtonFormField<String>(
                    value: _selectedDept,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    hint: const Text('كافة الأقسام', style: TextStyle(fontSize: 12)),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('كافة الأقسام', style: TextStyle(fontSize: 12))),
                      ..._departments.map((d) => DropdownMenuItem(
                            value: d['name'].toString(),
                            child: Text(d['name'].toString(), style: const TextStyle(fontSize: 12)),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedDept = val);
                      _loadEmployees();
                    },
                  ),
                ),
                const SizedBox(width: 12),

                // أزرار السوبر أدمن
                if (auth.isSuperAdmin) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: BorderSide(color: AppColors.navy.withOpacity(0.4)),
                    ),
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('استيراد من إكسل'),
                    onPressed: _importMasterEmployees,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('إضافة موظف'),
                    onPressed: () => _showEmployeeDialog(),
                  ),
                ],
              ],
            ),
          ),

          // قائمة الموظفين
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                    : _employees.isEmpty
                        ? const Center(child: Text('لا توجد سجلات مطابقة'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _employees.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final emp = _employees[index];
                              final isExempt = emp['is_exempt'] == 1;
                              final bool hasActiveLeave = emp['has_active_leave'] == 1;
                              final String status = (emp['status'] ?? '').toString().trim();
                              final String dept = (emp['department'] ?? '').toString().trim();
                              final bool isSeconded = status.contains('تنسيب') ||
                                  status.contains('نسب') ||
                                  dept.contains('تنسيب') ||
                                  dept.contains('نسب'); // يشمل أي موظف في قسم أو حالة التنسيب
                              final bool isTerminated = status.contains('استقال') ||
                                  status.contains('متوف') ||
                                  status.contains('انهاء') ||
                                  status.contains('منتهي') ||
                                  dept.contains('استقال') ||
                                  dept.contains('متوف'); // استقالة أو متوفى أو إنهاء خدمة

                              Color cardBgColor = Colors.white;
                              BorderSide cardBorder = BorderSide(color: Colors.grey.shade200);
                              Color accentColor = AppColors.navy;

                              if (hasActiveLeave) {
                                cardBgColor = _colorActiveLeave; // أزرق فاتح قابل للتخصيص
                                accentColor = const Color(0xFF1976D2);
                                cardBorder = BorderSide(color: accentColor.withOpacity(0.5), width: 1.5);
                              } else if (isTerminated) {
                                cardBgColor = _colorTerminated; // أحمر فاتح قابل للتخصيص
                                accentColor = const Color(0xFFD32F2F);
                                cardBorder = BorderSide(color: accentColor.withOpacity(0.5), width: 1.5);
                              } else if (isSeconded) {
                                cardBgColor = _colorSeconded; // برتقالي فاتح قابل للتخصيص
                                accentColor = const Color(0xFFE65100);
                                cardBorder = BorderSide(color: accentColor.withOpacity(0.5), width: 1.5);
                              } else if (isExempt) {
                                cardBgColor = _colorVipExempt;
                                accentColor = const Color(0xFF546E7A);
                                cardBorder = BorderSide(color: accentColor.withOpacity(0.5), width: 1.5);
                              }

                              final bool isSpecialStatus = hasActiveLeave || isTerminated || isSeconded || isExempt;

                              return Card(
                                color: cardBgColor,
                                elevation: isSpecialStatus ? 2 : 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: cardBorder,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: IntrinsicHeight(
                                  child: Row(
                                    children: [
                                      // شريط لوني جانبي بارز يوضح حالة الموظف
                                      Container(
                                        width: 6,
                                        color: isSpecialStatus ? accentColor : Colors.transparent,
                                      ),
                                      Expanded(
                                        child: ListTile(
                                          onTap: () => _showEmployeeProfileDialog(emp),
                                          leading: CircleAvatar(
                                            backgroundColor: accentColor,
                                            child: Text(
                                              '${emp['emp_code']}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                                            ),
                                          ),
                                          title: Wrap(
                                            spacing: 6,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              Text(emp['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                              if (hasActiveLeave)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF1976D2),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '🏖️ إجازة سارية: ${emp['active_leave_type'] ?? ''}',
                                                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              if (isTerminated)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFD32F2F),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    status.contains('متوف') ? '🕊️ متوفى' : '🛑 منتهي خدماته ($status)',
                                                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              if (isSeconded)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE65100),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text('📋 منسب / تنسيب', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                                ),
                                              if (isExempt)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF546E7A),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text('⭐ مستثنى VIP', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                                ),
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              '${emp['department']} • الحالة: ${emp['status']}' +
                                                  (emp['phone'] != null && emp['phone'].toString().isNotEmpty ? ' • 📞 ${emp['phone']}' : '') +
                                                  ' (انقر لعرض الملف والإجازات)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isTerminated
                                                    ? Colors.red.shade900
                                                    : (isSeconded ? Colors.brown.shade800 : (hasActiveLeave ? Colors.blue.shade900 : Colors.grey.shade700)),
                                              ),
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.assignment_ind_rounded, color: AppColors.navy),
                                                tooltip: 'عرض الملف وسجل الإجازات والتنقلات',
                                                onPressed: () => _showEmployeeProfileDialog(emp),
                                              ),
                                              if (auth.isSuperAdmin) ...[
                                        // زر النقل بين الأقسام
                                        IconButton(
                                          icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.navy),
                                          tooltip: 'نقل إلى قسم آخر',
                                          onPressed: () => _showTransferDialog(emp),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit_rounded, color: Colors.blueGrey),
                                          tooltip: 'تعديل البيانات',
                                          onPressed: () => _showEmployeeDialog(emp),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                          tooltip: 'حذف',
                                          onPressed: () => _deleteEmployee(emp),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
