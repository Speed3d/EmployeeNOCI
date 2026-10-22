import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';

/// Hint: نافذة رفع وتحليل كشف البصمة اليومي (.xlsx)
/// تدعم خياري: المعاينة فقط أو الحفظ والاعتماد المباشر (النقطة 8)
class UploadAttendanceDialog extends StatefulWidget {
  final Function(Map<String, dynamic> previewData) onPreviewLoaded;
  final VoidCallback onCommitted;

  const UploadAttendanceDialog({
    super.key,
    required this.onPreviewLoaded,
    required this.onCommitted,
  });

  @override
  State<UploadAttendanceDialog> createState() => _UploadAttendanceDialogState();
}

class _UploadAttendanceDialogState extends State<UploadAttendanceDialog> {
  String? _selectedFileName;
  Uint8List? _fileBytes;
  int? _fileSize;
  bool _isLoading = false;
  String? _loadingAction;
  String? _error;

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.xFile.readAsBytes();
        final size = await file.length();

        setState(() {
          _selectedFileName = file.name;
          _fileBytes = bytes;
          _fileSize = size;
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'تعذر اختيار الملف: $e');
    }
  }

  // إجراء 1: تحليل ومعاينة بدون حفظ
  Future<void> _previewOnly() async {
    if (_fileBytes == null || _selectedFileName == null) {
      setState(() => _error = 'يرجى اختيار ملف الإكسل أولاً');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingAction = 'جاري تحليل الملف للمعاينة...';
      _error = null;
    });

    try {
      final res = await ApiClient.instance.uploadFile(
        '/attendance/preview',
        _fileBytes!,
        _selectedFileName!,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onPreviewLoaded(res);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // إجراء 2: حفظ واعتماد مباشر
  Future<void> _commitDirect() async {
    if (_fileBytes == null || _selectedFileName == null) {
      setState(() => _error = 'يرجى اختيار ملف الإكسل أولاً');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingAction = 'جاري تحليل وحفظ واعتماد الكشف...';
      _error = null;
    });

    try {
      // أولاً نعاين لجلب التاريخ والبصمات
      final previewRes = await ApiClient.instance.uploadFile(
        '/attendance/preview',
        _fileBytes!,
        _selectedFileName!,
      );

      // ثم نرسل أمر الاعتماد
      await ApiClient.instance.post('/attendance/commit', {
        'date': previewRes['date'],
        'punchList': previewRes['rawPunches'],
      });

      if (mounted) {
        Navigator.pop(context);
        widget.onCommitted();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.onTime,
            content: Text('تم اعتماد كشف تاريخ ${previewRes['date']} وحفظه في قاعدة البيانات بنجاح!'),
          ),
        );
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
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.file_upload_rounded, color: AppColors.navy),
          SizedBox(width: 8),
          Text('رفع كشف البصمة اليومي'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'اختر ملف البصمة اليومي (.xlsx) المسحوب من جهاز البصمة للبدء:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // منطقة اختيار الملف
            InkWell(
              onTap: _isLoading ? null : _pickFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedFileName != null ? AppColors.onTime : Colors.grey.shade400,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: _selectedFileName != null
                      ? AppColors.onTime.withOpacity(0.05)
                      : Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFileName != null ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                      size: 40,
                      color: _selectedFileName != null ? AppColors.onTime : AppColors.navy,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedFileName ?? 'انقر هنا لاختيار ملف الإكسل',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _selectedFileName != null ? AppColors.onTime : AppColors.navy,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_fileSize != null)
                      Text(
                        'حجم الملف: ${(_fileSize! / 1024).toStringAsFixed(1)} كيلوبايت',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_isLoading) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Text(_loadingAction ?? 'جاري المعالجة...', style: const TextStyle(fontSize: 13)),
                ],
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        const Spacer(),
        // خيار 1: معاينة فقط
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.navy,
            side: const BorderSide(color: AppColors.navy),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          icon: const Icon(Icons.visibility_rounded, size: 18),
          label: const Text('تحليل ومعاينة فقط'),
          onPressed: (_fileBytes == null || _isLoading) ? null : _previewOnly,
        ),
        const SizedBox(width: 8),
        // خيار 2: حفظ واعتماد
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.onTime,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: const Text('حفظ واعتماد'),
          onPressed: (_fileBytes == null || _isLoading) ? null : _commitDirect,
        ),
      ],
    );
  }
}
