# 📦 حزمة التشغيل والنشر (NOCI Attendance Toolkit)

تحتوي هذه الحزمة على أدوات مؤتمتة لتشغيل وبناء ونشر النظام على الدومين وربطه بـ Cloudflare.

---

## 🚀 محتويات الحزمة:

1. **`run-local.bat` (تشغيل فوري محلي):**
   - بنقرة واحدة، يقوم بفحص قاعدة البيانات، وتغذية الموظفين الـ 292 تلقائياً، وتشغيل السيرفر واستضافة الويب على المنفذ `5000`.

2. **`setup-cloudflare-tunnel.ps1` (إعداد نفق Cloudflare):**
   - إعداد وتوجيه الدومين الفرعي `Employee.nociraq.com` إلى المنفذ الداخلي `5000` بدون الحاجة لـ IP ثابت وبدون فتح منافذ في الراوتر.

---

## 💻 أوامر البناء الأساسية:

* **بناء نسخة الويب (Web App):**
  ```powershell
  cd app
  flutter build web --release
  ```

* **بناء تطبيق الأندرويد (Android APK):**
  ```powershell
  cd app
  flutter build apk --release
  ```

* **بناء تطبيق ويندوز المكتبي (Windows Desktop):**
  ```powershell
  cd app
  flutter build windows --release
  ```

* **بناء تطبيق الآيفون على جهاز الماك (iOS App):**
  ```bash
  cd app
  flutter build ipa --release
  ```
