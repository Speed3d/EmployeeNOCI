# 📦 حزمة التشغيل والنشر (NOCI Attendance Toolkit)

أدوات تشغيل الخادم محلياً وفي الخلفية على جهاز واحد. للنشر على خادم وربطه بالدومين استعمل `deploy/`.

---

## 🚀 محتويات الحزمة

| الملف | الوظيفة |
|---|---|
| `run-local.bat` | تشغيل فوري في نافذة ظاهرة: يبذر الموظفين في قاعدة فارغة (ما لم تكن مُصفّرة عمداً)، ثم يشغّل الخادم على المنفذ `5000`. إغلاق النافذة يوقفه. |
| `install-startup-service.bat` | يربط الخادم بإقلاع الويندوز (تُشغَّل مرة واحدة). يعمل الخادم في الخلفية عبر المشرف `backend/scripts/run-forever.js` الذي يعيد تشغيله تلقائياً عند أي تعطل، ويكتب السجل في `backend/logs/server.log`. |
| `run-silent.vbs` | يشغّل المشرف في الخلفية دون نافذة، ويستخدمه ملف الإقلاع التلقائي. |
| `stop-server.bat` | يوقف المشرف أولاً ثم أي خادم على المنفذ 5000. |
| `deploy/` | **حزمة النشر على خادم:** بناء الحزمة، والتثبيت في `C:\NOCI`، والخادم كخدمة دائمة، ونفق Cloudflare لـ `https://employee.nociraq.com`، والتحديث مع الحفاظ على البيانات. الدليل في [deploy/README.md](deploy/README.md). |

> `install-startup-service.bat` يعمل بعد تسجيل دخول المستخدم فقط. على الخادم الفعلي استعمل `deploy/` (الخطوة 4)، فهي تشغّل الخادم عند الإقلاع حتى دون تسجيل دخول.

---

## 💻 أوامر البناء

شغّل الاختبارات قبل أي بناء:
```powershell
cd backend; npm test
cd ..\app; flutter analyze; flutter test
```

| النسخة | الأمر | الناتج |
|---|---|---|
| الويب | `cd app; flutter build web --release` | `app/build/web` (يستضيفه الخادم تلقائياً) |
| ويندوز | `cd app; flutter build windows --release` | `app/build/windows/x64/runner/Release/` |
| أندرويد | `cd app; flutter build apk --release` | `app/build/app/outputs/flutter-apk/app-release.apk` |
| آيفون (على الماك) | `cd app; flutter build ipa --release` | — |

التفاصيل في [دليل البناء والنشر](../خطط/دليل_البناء_والنشر_ويندوز_وماك.md) و[دليل التثبيت والتحديث](../خطط/دليل_تثبيت_الإصدار_2.0.0.md).
