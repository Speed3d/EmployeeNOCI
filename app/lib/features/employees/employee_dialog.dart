import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/custom_button.dart';

/// Hint: نافذة إضافة أو تعديل بيانات الموظف
class EmployeeDialog extends StatefulWidget {
  final Map<String, dynamic>? employee;
  final VoidCallback onSaved;

  const EmployeeDialog({super.key, this.employee, required this.onSaved});

  @override
  State<EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<EmployeeDialog> {
  late TextEditingController _codeController;
  late TextEditingController _nameController;
  late TextEditingController _deptController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _exemptReasonController;

  String _status = 'نشط';
  bool _isExempt = false;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _codeController = TextEditingController(text: e?['emp_code']?.toString() ?? '');
    _nameController = TextEditingController(text: e?['name']?.toString() ?? '');
    _deptController = TextEditingController(text: e?['department']?.toString() ?? 'قسم الادارة');
    _phoneController = TextEditingController(text: e?['phone']?.toString() ?? '');
    _addressController = TextEditingController(text: e?['address']?.toString() ?? '');
    _exemptReasonController = TextEditingController(text: e?['exempt_reason']?.toString() ?? '');

    _status = e?['status']?.toString() ?? 'نشط';
    _isExempt = e?['is_exempt'] == 1 || e?['is_exempt'] == true;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _deptController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _exemptReasonController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final dept = _deptController.text.trim();

    if (code.isEmpty || name.isEmpty || dept.isEmpty) {
      setState(() => _error = 'المعرف، الاسم، والقسم حقول إلزامية');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final body = {
        'empCode': code,
        'name': name,
        'department': dept,
        'status': _status,
        'isExempt': _isExempt,
        'exemptReason': _isExempt ? _exemptReasonController.text.trim() : '',
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
      };

      if (widget.employee == null) {
        await ApiClient.instance.post('/employees', body);
      } else {
        await ApiClient.instance.put('/employees/${widget.employee!['id']}', body);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.employee != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(isEditing ? Icons.edit_rounded : Icons.person_add_rounded, color: AppColors.navy),
          const SizedBox(width: 8),
          Text(isEditing ? 'تعديل بيانات الموظف' : 'إضافة موظف جديد'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(labelText: 'معرف البصمة (كود) *'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'الاسم الكامل للموظف *'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _deptController,
                      decoration: const InputDecoration(labelText: 'القسم *'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _status,
                      decoration: const InputDecoration(labelText: 'الحالة الوظيفية'),
                      items: const [
                        DropdownMenuItem(value: 'نشط', child: Text('نشط في الدوام')),
                        DropdownMenuItem(value: 'استقالة', child: Text('استقالة')),
                        DropdownMenuItem(value: 'تنسيب', child: Text('تنسيب خارج المقر')),
                        DropdownMenuItem(value: 'متوفى', child: Text('متوفى')),
                      ],
                      onChanged: (val) => setState(() => _status = val ?? 'نشط'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'عنوان السكن'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // خيار استثناء الـ VIP
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('استثناء قيادي (VIP) من البصمة والغياب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: const Text('الأمين العام، الأمين المالي، المستشارين ومن في حكمهم', style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: _isExempt,
                onChanged: (val) => setState(() => _isExempt = val),
              ),

              if (_isExempt) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _exemptReasonController,
                  decoration: const InputDecoration(
                    labelText: 'سبب الاستثناء (مثال: الأمين العام)',
                    prefixIcon: Icon(Icons.star_rounded, color: AppColors.goldBright),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        CustomButton(
          label: isEditing ? 'تحديث البيانات' : 'حفظ الموظف',
          icon: Icons.check_rounded,
          isLoading: _isLoading,
          onPressed: _save,
        ),
      ],
    );
  }
}
