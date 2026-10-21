import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../shared/custom_button.dart';
import '../../tools/responsive.dart';
import 'employee_dialog.dart';

/// Hint: شاشة إدارة سجلات الموظفين ودليل المقر
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _employees = [];
  String _searchQuery = '';
  String? _selectedDept;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
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

  void _showEmployeeDialog([Map<String, dynamic>? employee]) {
    showDialog(
      context: context,
      builder: (ctx) => EmployeeDialog(
        employee: employee,
        onSaved: _loadEmployees,
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
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      body: Column(
        children: [
          // شريط البحث والعمليات
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'بحث باسم الموظف، المعرف، أو الهاتف...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) {
                      _searchQuery = val.trim();
                      _loadEmployees();
                    },
                  ),
                ),
                const SizedBox(width: 14),
                CustomButton(
                  label: 'إضافة موظف',
                  icon: Icons.person_add_rounded,
                  onPressed: () => _showEmployeeDialog(),
                ),
              ],
            ),
          ),

          // عدد النتائج
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  'إجمالي الموظفين: ${_employees.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),

          // قائمة الموظفين
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _employees.isEmpty
                    ? const Center(child: Text('لم يتم العثور على أي موظف'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        itemCount: _employees.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final emp = _employees[index];
                          final isExempt = emp['is_exempt'] == 1 || emp['is_exempt'] == true;
                          final status = emp['status'] ?? 'نشط';

                          return Card(
                            elevation: 0,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isExempt ? AppColors.goldBright.withOpacity(0.2) : AppColors.navy.withOpacity(0.1),
                                child: Text(
                                  '${emp['emp_code']}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isExempt ? AppColors.goldDark : AppColors.navy,
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    emp['name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  if (isExempt) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.goldDark.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star_rounded, size: 12, color: AppColors.goldDark),
                                          const SizedBox(width: 4),
                                          Text(
                                            emp['exempt_reason'] ?? 'مستثنى VIP',
                                            style: const TextStyle(fontSize: 10, color: AppColors.goldDark, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (status != 'نشط') ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        status,
                                        style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                '${emp['department']}${emp['phone'] != null && emp['phone'].toString().isNotEmpty ? ' • ${emp['phone']}' : ''}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    tooltip: 'تعديل',
                                    onPressed: () => _showEmployeeDialog(emp),
                                  ),
                                  if (auth.isSuperAdmin)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                                      tooltip: 'حذف',
                                      onPressed: () => _deleteEmployee(emp),
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
