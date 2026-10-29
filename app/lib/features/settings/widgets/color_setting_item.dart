import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Hint: تحويل لون نصي (#RRGGBB) إلى Color مع قيمة بديلة عند الخطأ
Color parseHexColor(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  try {
    String clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) clean = 'FF$clean';
    return Color(int.parse(clean, radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// Hint: عناصر تبويب ألوان حالات الموظفين (منتقي اللون والمعاينة المصغرة)

Widget buildColorSettingItem({
  required String title,
  required String subtitle,
  required String currentColorHex,
  required List<String> palette,
  required ValueChanged<String> onColorSelected,
}) {
  final current = parseHexColor(currentColorHex, Colors.white);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 12),
      Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: current,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade400, width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2))],
            ),
          ),
          const SizedBox(width: 14),
          for (final hex in palette)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: InkWell(
                onTap: () => onColorSelected(hex),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: parseHexColor(hex, Colors.white),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: currentColorHex.toLowerCase() == hex.toLowerCase() ? AppColors.navy : Colors.grey.shade300,
                      width: currentColorHex.toLowerCase() == hex.toLowerCase() ? 2.5 : 1,
                    ),
                  ),
                  child: currentColorHex.toLowerCase() == hex.toLowerCase() ? const Icon(Icons.check_rounded, size: 16, color: AppColors.navy) : null,
                ),
              ),
            ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            height: 36,
            child: TextFormField(
              initialValue: currentColorHex,
              key: ValueKey(currentColorHex),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (val) {
                if (val.trim().isNotEmpty) onColorSelected(val.trim());
              },
            ),
          ),
        ],
      ),
    ],
  );
}

Widget buildMiniCardPreview(String label, String tag, Color bg, Color accent) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: accent.withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
          child: Text(
            tag,
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}
