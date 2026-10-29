import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../tools/date_formatter.dart';
import '../../core/theme.dart';
import '../../tools/responsive.dart';

/// Hint: شاشة سجل الحركات والتدقيق الأمني (Audit Logs)
/// مخصصة للسوبر أدمن لمتابعة كل حركة وتعديل يجريه أي مستخدم بالنظام
class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _logs = [];
  String _searchQuery = '';
  int _totalLogs = 0;

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
  }

  Future<void> _loadAuditLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String url = '/audit-logs?limit=150';
      if (_searchQuery.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(_searchQuery)}';
      }

      final res = await ApiClient.instance.get(url);
      if (!mounted) return;
      setState(() {
        _logs = res['logs'] ?? [];
        _totalLogs = res['total'] ?? 0;
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      body: Column(
        children: [
          // شريط البحث
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
                      hintText: 'بحث في سجل الحركات (المستخدم، الإجراء، أو التفاصيل)...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) {
                      _searchQuery = val.trim();
                      _loadAuditLogs();
                    },
                  ),
                ),
                const SizedBox(width: 14),
                IconButton(
                  tooltip: 'تحديث السجل',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loadAuditLogs,
                ),
              ],
            ),
          ),

          // عدد العمليات
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  'إجمالي الحركات الموثقة: $_totalLogs حركة',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),

          // قائمة السجلات
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                    : _logs.isEmpty
                        ? const Center(child: Text('لا توجد حركات مسجلة تطابق البحث'))
                        : isDesktop
                            ? _buildDesktopTable()
                            : _buildMobileList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.navy.withValues(alpha: 0.06)),
            columns: const [
              DataColumn(label: Text('المعرف #', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الوقت والتاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('المستخدم', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الإجراء المتخذ', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('التفاصيل الدقيقة', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('عنوان IP', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: _logs.map((l) {
              return DataRow(
                cells: [
                  DataCell(Text('#${l['id']}')),
                  DataCell(Text(DateFormatter.dbTimestampToLocal(l['created_at']), style: const TextStyle(fontSize: 12))),
                  DataCell(
                    Row(
                      children: [
                        const Icon(Icons.person_pin_rounded, size: 16, color: AppColors.navy),
                        const SizedBox(width: 6),
                        Text(l['user_name'] ?? 'مجهول', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l['action'] ?? '',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navy),
                      ),
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 350),
                      child: Text(
                        l['details'] ?? '',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text(l['ip_address'] ?? 'محلي', style: const TextStyle(fontSize: 11, color: Colors.grey))),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _logs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final l = _logs[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l['user_name'] ?? 'مستخدم',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.navy),
                    ),
                    Text(DateFormatter.dbTimestampToLocal(l['created_at']), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.goldBright.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l['action'] ?? '',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.goldDark),
                  ),
                ),
                const SizedBox(height: 6),
                Text(l['details'] ?? '', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}
