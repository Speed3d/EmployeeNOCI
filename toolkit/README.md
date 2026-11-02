# 📦 حزمة التشغيل والنشر (NOCI Attendance Toolkit)

أدوات تشغيل الخادم محلياً وفي الخلفية، وربطه بالدومين عبر Cloudflare.

---

## 🚀 محتويات الحزمة

| الملف | الوظيفة |
|---|---|
| `run-local.bat` | تشغيل فوري في نافذة ظاهرة: يبذر الموظفين في قاعدة فارغة (ما لم تكن مُصفّرة عمداً)، ثم يشغّل الخادم على المنفذ `5000`. إغلاق النافذة يوقفه. |
| `install-startup-service.bat` | يربط الخادم بإقلاع الويندوز (تُشغَّل مرة واحدة). يعمل الخادم في الخلفية عبر المشرف `backend/scripts/run-forever.js` الذي يعيد تشغيله تلقائياً عند أي تعطل، ويكتب السجل في `backend/logs/server.log`. |
| `run-silent.vbs` | يشغّل المشرف في الخلفية دون نافذة، ويستخدمه ملف الإقلاع التلقائي. |
| `stop-server.bat` | يوقف المشرف أولاً ثم أي خادم على المنفذ 5000. |
| `setup-cloudflare-tunnel.ps1` | يثبّت cloudflared (عبر winget أو مع فحص التوقيع الرقمي)، وينشئ النفق ويربط `Employee.nociraq.com` بالمنفذ `5000` دون IP ثابت ودون فتح منافذ في الراوتر. |

> عند الاكتفاء بالنشر عبر Cloudflare أضف `HOST=127.0.0.1` إلى `backend/.env` حتى لا يُقبل اتصال غير مشفر من الشبكة المحلية.

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
