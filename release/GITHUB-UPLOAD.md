# رفع ملفات نور الروح كاملة

المستودع الظاهر في لقطة سعود على Codemagic: https://github.com/saud1596x/nor-alroh . الربط ظاهر في حسابه، لكن Codemagic لم يجد YAML في اللقطة. لا يوجد اتصال مصادق إلى المستودع في بيئة العمل هذه ولم تُدفع الملفات إليه.

## من Windows باستخدام GitHub Desktop

1. حمّل `noor-alroh-github-upload.zip` وفك الضغط؛ ملفات الرفع فيه مباشرة دون مجلد خارجي. يجب أن ترى `codemagic.yaml` و`ios` و`scripts` و`release` و`support-site`. حزمة `noor-alruh-ios-source.zip` البديلة تحتوي مجلدًا خارجيًا `noor-alruh-ios`؛ عند استخدامها انسخ محتويات ذلك المجلد.
2. ثبّت GitHub Desktop من https://desktop.github.com/ وسجّل بحساب `saud1596x`.
3. اختر File → Clone repository ثم مستودع `nor-alroh`، واحفظ نسخته في مجلد على الكمبيوتر. إذا كان المستودع فارغًا تمامًا، أنشئ له README من GitHub أولًا ليصبح له فرع يمكن استنساخه.
4. إذا توجد ملفات أو تطبيق سابق في المستودع، أنشئ فرعًا `noor-native` ولا تمسح الملفات السابقة عشوائيًا. افتح مجلد النسخة من Repository → Show in Explorer.
5. انسخ ملفات حزمة الرفع المفكوكة إلى جذر النسخة المستنسخة، لا المجلد الخارجي ولا ZIP. راجع ملفات التغيير في GitHub Desktop قبل الاستبدال والـCommit.
6. يجب أن يصبح `codemagic.yaml` بجوار `ios` في أعلى المستودع، لا داخل `noor-alruh-ios/codemagic.yaml`. اعمل Commit برسالة مثل `Prepare Noor Alroh native app and privacy pages`، ثم Push origin أو Publish branch للفرع الجديد.
7. افتح GitHub وتحقق أن `codemagic.yaml` و`ios/Athar` و`scripts` ظاهرة على الفرع نفسه. في Codemagic حدّث الفروع واختر الفرع الذي رفعت إليه الملفات، ثم تحقق من ملفات التكوين. سيظهر مسارا `ios-quality` و`ios-testflight`.

رفع ZIP وحده أو YAML وحده لا يوفر مصدر التطبيق للبناء. الحزمة لا تتضمن شهادات أو مفاتيح Apple أو ملفات QCF الخام؛ توجد ملفات `.gitignore` واستثناءات التغليف المناسبة.

## صفحات الخصوصية والدعم

مجلد `support-site` يحتوي `privacy.html` و`support.html` و`terms.html` و`index.html`، دون تسجيل دخول أو تحليلات أو كوكيز أو نماذج تجمع بيانات. يمكن استضافة **محتويات هذا المجلد فقط** على خدمة HTTPS تختارها. لا تنشر مجلد المصدر كاملًا كموقع، ولا تفترض أن مستودعًا خاصًا يدعم GitHub Pages في خطتك.

عند نشرها، افتح روابطها من متصفح غير مسجل دخول وتأكد أنها عامة وتعرض البريد الصحيح. بعدها أدخل الروابط الفعلية في `release/config.json` تحت `privacyURL` و`supportURL` و`termsURL`، ثم شغّل:

```sh
python scripts/prepare-publishing.py
python scripts/prepare-publishing.py --check
```

اعمل Commit/Push للملفات المتولدة أيضًا. لا يضع السكربت روابط مخمنة في التطبيق ولا ينشر الموقع بنفسه. صفحات التطبيق والويب تُولد من `release/legal-content.json` نفسه لمنع اختلاف نص سياسة الخصوصية.
