import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/custom_button.dart';

/// Hint: نافذة رفع واستيراد ملف كشف البصمة اليومي (.xlsx)
class UploadAttendanceDialog extends StatefulWidget {
  final VoidCallback onUploaded;
  const UploadAttendanceDialog({super.key, required this.onUploaded});

  @override
  State<UploadAttendanceDialog> createState() => _UploadAttendanceDialogState();
}

class _UploadAttendanceDialogState extends State<UploadAttendanceDialog> {
  String? _selectedFileName;
  Uint8List? _fileBytes;
  int? _fileSize;
  bool _isUploading = false;
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

  Future<void> _upload() async {
    if (_fileBytes == null || _selectedFileName == null) {
      setState(() => _error = 'يرجى اختيار ملف الإكسل أولاً');
      return;
    }

    setState(() {
      _isUploading = true;
      _error = null;
    });

    try {
      await ApiClient.instance.uploadFile(
        '/attendance/upload',
        _fileBytes!,
        _selectedFileName!,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onUploaded();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.onTime,
            content: Text('تم استيراد وتحليل كشف البصمة بنجاح!'),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isUploading = false;
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
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'اختر ملف الإكسل اليومي المستخرج من جهاز البصمة (مثل نموذج 20-10-2026.xlsx) لتحليله وتشخيصه فوراً:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // منطقة اختيار الملف
            InkWell(
              onTap: _isUploading ? null : _pickFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.navy.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedFileName != null ? AppColors.onTime : AppColors.navy.withOpacity(0.3),
                    style: BorderStyle.solid,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFileName != null ? Icons.description_rounded : Icons.cloud_upload_outlined,
                      size: 44,
                      color: _selectedFileName != null ? AppColors.onTime : AppColors.navy,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _selectedFileName ?? 'اضغط لاختيار ملف الإكسل (.xlsx)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _selectedFileName != null ? AppColors.onTime : AppColors.navy,
                      ),
                    ),
                    if (_fileSize != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'الحجم: ${(_fileSize! / 1024).toStringAsFixed(1)} كيلوبايت',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        CustomButton(
          label: 'تحليل واعتماد الكشف',
          icon: Icons.check_circle_outline_rounded,
          isLoading: _isUploading,
          onPressed: _fileBytes != null ? _upload : null,
        ),
      ],
    );
  }
}
