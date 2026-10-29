import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../core/constants.dart';
import '../../shared/status_badge.dart';
import '../../tools/date_formatter.dart';
import 'upload_dialog.dart';

/// Hint: شاشة كشف البصمة اليومي والتحليل والمعاينة والاعتماد (الإصدار الثاني المعتمد)
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  // النقطة 3: التاريخ الافتراضي = تاريخ الحاسوب الحالي
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _error;

  List<dynamic> _records = [];
  List<dynamic> _allDepartments = [];

  String _searchQuery = '';
  String? _selectedDept;
  String? _selectedStatus;

  // النقطة 8: متغيرات وضع المعاينة المؤقتة
  bool _isPreviewMode = false;
  String? _previewId;
  List<dynamic> _previewDays = [];
  String? _previewDate;
  bool _isCommitted = false;
  String? _committedByName;
  String? _committedAt;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
    _loadDailyAttendance();
  }

  Future<void> _loadDepartments() async {
    try {
      final res = await ApiClient.instance.get('/employees/departments');
      if (res is List && mounted) {
        setState(() {
          _allDepartments = res;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDailyAttendance() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _isPreviewMode = false;
    });

    try {
      final dateStr = DateFormatter.toYmd(_selectedDate);
      String url = '/attendance/daily?date=$dateStr';

      if (_selectedDept != null && _selectedDept!.isNotEmpty) {
        url += '&department=${Uri.encodeComponent(_selectedDept!)}';
      }
      if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
        url += '&status=$_selectedStatus';
      }
      if (_searchQuery.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(_searchQuery)}';
      }

      final res = await ApiClient.instance.get(url);
      if (!mounted) return;
      setState(() {
        _records = res['records'] ?? [];
        _isCommitted = res['isCommitted'] ?? false;
        _committedByName = res['committedByName'];
        _committedAt = res['committedAt'];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // تفعيل وضع المعاينة القادم من نافذة الرفع (يوم واحد أو عدة أيام)
  void _onPreviewLoaded(Map<String, dynamic> previewData) {
    final days = List<dynamic>.from(previewData['days'] ?? []);
    if (!mounted) return;
    setState(() {
      _isPreviewMode = true;
      _previewId = previewData['previewId'];
      _previewDays = days;
      _isLoading = false;
    });
    if (days.isNotEmpty) _selectPreviewDay(days.first['date']);

    final invalidRows = previewData['invalidRows'] ?? 0;
    if (days.length > 1 || invalidRows > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            (days.length > 1 ? 'يحتوي الملف على ${days.length} أيام، يرجى معاينة واعتماد كل يوم على حدة. ' : '') +
                (invalidRows > 0 ? 'تم تجاهل $invalidRows صف بصيغة غير صالحة.' : ''),
          ),
        ),
      );
    }
  }

  void _selectPreviewDay(String date) {
    final day = _previewDays.firstWhere((d) => d['date'] == date, orElse: () => null);
    if (day == null) return;
    if (!mounted) return;
    setState(() {
      _previewDate = date;
      _records = day['records'] ?? [];
      _isCommitted = day['isCommitted'] ?? false;
    });
  }

  // حفظ واعتماد اليوم المعاين حالياً (بمعرف المعاينة المحفوظة في الخادم)
  Future<void> _commitPreviewedAttendance() async {
    if (_previewDate == null || _previewId == null) return;

    final auth = AuthProvider.instance;
    if (_isCommitted && !auth.canRecommit) {
      _showErrorDialog('تنبيه الاعتماد', 'هذا اليوم معتمد مسبقاً، وإعادة الاعتماد تتطلب صلاحية خاصة من السوبر أدمن.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final committedDate = _previewDate!;
    setState(() => _isLoading = true);
    try {
      await ApiClient.instance.post('/attendance/commit', {
        'previewId': _previewId,
        'date': committedDate,
      });
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text('تم اعتماد كشف تاريخ $committedDate وحفظه رسمياً بنجاح!'),
        ),
      );

      // Hint: إذا بقيت أيام غير معتمدة في نفس الملف ننتقل إليها، وإلا نعرض اليوم المعتمد
      for (final d in _previewDays) {
        if (d['date'] == committedDate) d['isCommitted'] = true;
      }
      final remaining = _previewDays.where((d) => d['isCommitted'] != true).toList();
      if (remaining.isNotEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _selectPreviewDay(remaining.first['date']);
      } else {
        _selectedDate = DateTime.parse(committedDate);
        _loadDailyAttendance();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorDialog('فشل الاعتماد', e.toString());
    }
  }

  // إعادة احتساب يوم معتمد بقواعد يوم الاعتماد أو بالقواعد الحالية
  Future<void> _recalculateDay(bool useCurrentRules) async {
    final dateStr = DateFormatter.toYmd(_selectedDate);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة احتساب اليوم'),
        content: Text(useCurrentRules
            ? 'سيُعاد احتساب كشف $dateStr وفق إعدادات الدوام الحالية، وقد تتغير نتائجه عن يوم الاعتماد. هل تريد المتابعة؟'
            : 'سيُعاد احتساب كشف $dateStr بنفس قواعد يوم اعتماده (مع تطبيق الإجازات والعطل الحالية). هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إعادة الاحتساب')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiClient.instance.post('/attendance/recalculate', {'date': dateStr, 'useCurrentRules': useCurrentRules});
      messenger.showSnackBar(const SnackBar(backgroundColor: AppColors.onTime, content: Text('تمت إعادة احتساب اليوم بنجاح')));
      _loadDailyAttendance();
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('تعذرت إعادة الاحتساب', e.toString());
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  void _changeDate(int days) {
    if (!mounted) return;
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadDailyAttendance();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate && mounted) {
      setState(() => _selectedDate = picked);
      _loadDailyAttendance();
    }
  }

  // تصدير الإكسل المباشر مع دعم فلاتر القسم والحالة (برابط تنزيل مؤقت)
  Future<void> _exportExcel() async {
    if (_isPreviewMode) {
      _showErrorDialog('التصدير غير متاح', 'لا يمكن تصدير كشف في وضع المعاينة؛ يرجى اعتماده أولاً.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ApiClient.instance.downloadUrl('export-daily', {
        'date': DateFormatter.toYmd(_selectedDate),
        if (_selectedDept != null && _selectedDept!.isNotEmpty) 'department': _selectedDept,
        if (_selectedStatus != null && _selectedStatus!.isNotEmpty) 'status': _selectedStatus,
      });
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح رابط تصدير الإكسل')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذر التصدير: $e')));
    }
  }

  // النقطة 5: نافذة استثناء الأقسام
  void _showExcludeDeptsDialog() {
    final auth = AuthProvider.instance;
    if (!auth.canManageExclusions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('تعديل استثناء الأقسام محصور بالسوبر أدمن أو من يملك صلاحية الاستثناءات'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.filter_alt_off_rounded, color: AppColors.navy),
                SizedBox(width: 8),
                Text('إدارة استثناء الأقسام من الكشوفات'),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 400,
              child: _allDepartments.isEmpty
                  ? const Center(child: Text('لا توجد أقسام مسجلة'))
                  : ListView.separated(
                      itemCount: _allDepartments.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final dept = _allDepartments[index];
                        final isExcluded = dept['is_excluded'] == 1;
                        return SwitchListTile(
                          title: Text(
                            dept['name'],
                            style: TextStyle(
                              fontWeight: isExcluded ? FontWeight.normal : FontWeight.bold,
                              color: isExcluded ? Colors.grey : AppColors.navy,
                            ),
                          ),
                          subtitle: Text(
                            isExcluded ? 'مستبعد من الحضور والتقارير' : 'مشمول بالبصمة',
                            style: TextStyle(fontSize: 12, color: isExcluded ? AppColors.danger : AppColors.onTime),
                          ),
                          value: isExcluded,
                          activeThumbColor: AppColors.danger,
                          onChanged: (val) async {
                            try {
                              await ApiClient.instance.put('/employees/departments/${dept['id']}/exclusion', {
                                'isExcluded': val,
                              });
                              setDialogState(() {
                                dept['is_excluded'] = val ? 1 : 0;
                              });
                              _loadDepartments();
                              _loadDailyAttendance();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطأ: $e')),
                              );
                            }
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentDateStr = _isPreviewMode ? (_previewDate ?? '') : DateFormatter.toYmd(_selectedDate);

    // تطبيق الفلترة المحلية السريعة
    final displayedRecords = _records.where((r) {
      if (_selectedDept != null && _selectedDept!.isNotEmpty && r['department'] != _selectedDept) {
        return false;
      }
      if (_selectedStatus != null && _selectedStatus!.isNotEmpty && r['status'] != _selectedStatus) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = (r['name'] ?? '').toString().toLowerCase();
        final code = (r['emp_code'] ?? r['empCode'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !code.contains(q)) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          // شريط المعاينة والاعتماد التحذيري البارز
          if (_isPreviewMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.amber.shade700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.visibility_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'وضع المعاينة المؤقتة لكشف تاريخ [$_previewDate]'
                          '${_isCommitted ? ' (هذا اليوم معتمد مسبقاً وسيُعاد اعتماده)' : ' (لم يُحفظ بعد ولن يظهر بالتقارير إلا بعد اعتماده)'}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  if (_previewDays.length > 1) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d in _previewDays)
                          ChoiceChip(
                            label: Text('${d['date']}${d['isCommitted'] == true ? ' ✓' : ''}'),
                            selected: d['date'] == _previewDate,
                            onSelected: (_) => _selectPreviewDay(d['date']),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.onTime,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(
                          _previewDays.length > 1 ? 'اعتماد يوم $_previewDate' : 'حفظ واعتماد الكشف الآن',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isLoading ? null : _commitPreviewedAttendance,
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('إنهاء المعاينة'),
                        onPressed: () {
                          if (!mounted) return;
                          setState(() {
                            _isPreviewMode = false;
                            _previewId = null;
                            _previewDays = [];
                          });
                          _loadDailyAttendance();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // شريط حالة الاعتماد في الأيام المسجلة
          if (!_isPreviewMode && _isCommitted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: AppColors.onTime.withValues(alpha: 0.12),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: AppColors.onTime, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'هذا الكشف معتمد رسمياً'
                      '${_committedByName != null ? ' بواسطة [$_committedByName]' : ''}'
                      '${_committedAt != null ? ' بتاريخ ${DateFormatter.dbTimestampToLocal(_committedAt)}' : ''}',
                      style: const TextStyle(color: AppColors.onTime, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  if (AuthProvider.instance.canRecommit)
                    PopupMenuButton<bool>(
                      tooltip: 'إعادة احتساب اليوم',
                      icon: const Icon(Icons.refresh_rounded, color: AppColors.onTime, size: 20),
                      onSelected: _recalculateDay,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: false, child: Text('إعادة احتساب بنفس قواعد يوم الاعتماد')),
                        PopupMenuItem(value: true, child: Text('إعادة احتساب بالقواعد الحالية')),
                      ],
                    ),
                ],
              ),
            ),

          // الشريط العلوي للأدوات والفلاتر والتحكم
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color ?? Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                // محدد التاريخ والأسهم
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      tooltip: 'اليوم السابق',
                      onPressed: _isPreviewMode ? null : () => _changeDate(-1),
                    ),
                    InkWell(
                      onTap: _isPreviewMode ? null : _selectDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.navy.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.navy),
                            const SizedBox(width: 8),
                            Text(
                              DateFormatter.toArabicDate(currentDateStr),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      tooltip: 'اليوم التالي',
                      onPressed: _isPreviewMode ? null : () => _changeDate(1),
                    ),
                  ],
                ),

                // أزرار العمليات الرئيسية
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // زر استثناء الأقسام
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: BorderSide(color: AppColors.navy.withValues(alpha: 0.4)),
                      ),
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                      label: const Text('استثناء أقسام'),
                      onPressed: _showExcludeDeptsDialog,
                    ),

                    // زر تصدير الإكسل
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.onTime,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('تصدير إكسل'),
                      onPressed: _exportExcel,
                    ),

                    // زر رفع الكشف اليومي
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                      label: const Text('رفع كشف البصمة'),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => UploadAttendanceDialog(
                            onPreviewLoaded: _onPreviewLoaded,
                            onCommitted: _loadDailyAttendance,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // شريط الفلاتر والبحث
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).cardTheme.color?.withValues(alpha: 0.5) ?? Colors.grey.shade50,
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // البحث بالاسم أو الكود
                SizedBox(
                  width: 220,
                  height: 38,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم أو المعرف...',
                      hintStyle: const TextStyle(fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),

                // فلتر القسم
                SizedBox(
                  width: 200,
                  height: 38,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedDept,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    hint: const Text('كافة الأقسام', style: TextStyle(fontSize: 12)),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('كافة الأقسام', style: TextStyle(fontSize: 12))),
                      ..._allDepartments
                          .where((d) => d['is_excluded'] == 0) // إخفاء الأقسام المستبعدة تماماً
                          .map((d) => DropdownMenuItem(
                                value: d['name'].toString(),
                                child: Text(d['name'].toString(), style: const TextStyle(fontSize: 12)),
                              )),
                    ],
                    onChanged: (val) => setState(() => _selectedDept = val),
                  ),
                ),

                // فلتر الحالة (حذف مستثنى VIP والأقسام المستبعدة بناء على النقطة 7)
                SizedBox(
                  width: 170,
                  height: 38,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedStatus,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    hint: const Text('كافة الحالات', style: TextStyle(fontSize: 12)),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('كافة الحالات', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'ON_TIME', child: Text('حضور نظامي (أخضر)', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'LATE', child: Text('تأخير بسيط (أصفر)', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'VERY_LATE', child: Text('تأخير كبير (برتقالي)', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'EARLY_LEAVE', child: Text('انصراف مبكر', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'MISSED_PUNCH', child: Text('بصمة ناقصة (بنفسجي)', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'ABSENT', child: Text('غائب (أحمر)', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'ON_LEAVE', child: Text('مجاز رسمي', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'OFF_DAY', child: Text('يوم راحة', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'HOLIDAY', child: Text('عطلة رسمية', style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (val) => setState(() => _selectedStatus = val),
                  ),
                ),

                // عداد السجلات الظاهرة
                Text(
                  'النتائج: ${displayedRecords.length} موظف',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.navy),
                ),
              ],
            ),
          ),

          // جدول كشف الحضور الرئيسي
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                    : displayedRecords.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_rounded, size: 48, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('لا توجد بيانات مسجلة لهذا التاريخ أو الفلتر المختار'),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: displayedRecords.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final r = displayedRecords[index];
                              final status = r['status'] ?? 'ABSENT';
                              final statusColor = AppConstants.getStatusColor(status);

                              return Container(
                                color: index % 2 == 0 ? Colors.transparent : Colors.grey.withValues(alpha: 0.02),
                                child: ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: statusColor.withValues(alpha: 0.12),
                                    child: Text(
                                      '${r['emp_code'] ?? r['empCode'] ?? ''}',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: statusColor),
                                    ),
                                  ),
                                  title: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: r['name'] ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        TextSpan(
                                          text: '  (${r['department'] ?? ''})',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'الدخول: ${DateFormatter.formatTime12h(r['first_punch'] ?? r['firstPunch'])}  |  الخروج: ${DateFormatter.formatTime12h(r['last_punch'] ?? r['lastPunch'])}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      if (r['notes'] != null && r['notes'].toString().isNotEmpty)
                                        Text(
                                          '• ${r['notes']}',
                                          style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                  trailing: StatusBadge(status: status),
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
