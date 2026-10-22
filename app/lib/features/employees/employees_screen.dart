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

  @override
  void initState() {
    super.initState();
    _loadDepartments();
    _loadEmployees();
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

                              return Card(
                                elevation: 1,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.navy.withOpacity(0.1),
                                    child: Text(
                                      '${emp['emp_code']}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy, fontSize: 13),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Text(emp['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(width: 8),
                                      if (isExempt)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.vipExempt.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('مستثنى VIP', style: TextStyle(fontSize: 10, color: AppColors.vipExempt, fontWeight: FontWeight.bold)),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${emp['department']} • الحالة: ${emp['status']}' +
                                        (emp['phone'] != null && emp['phone'].toString().isNotEmpty ? ' • 📞 ${emp['phone']}' : ''),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: auth.isSuperAdmin
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
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
                                        )
                                      : null,
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
