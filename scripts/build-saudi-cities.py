"""Build selected Saudi city centres from a local GeoNames SA.txt input."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
# Arabic display names maintained by the project. Coordinates come from GeoNames.
labels='''100425|ينبع
100926|أملج
101035|أم الساهك
101312|طريف
101322|تربة
101516|تيماء
101554|تاروت
101628|تبوك
101631|طبرجل
101732|عنيزة
102170|شقراء
102318|سيهات
102451|صامطة
102527|سكاكا
102585|صفوى
102651|صبيا
102744|رماح
102891|رأس تنورة
103035|رابغ
103220|قبة
103369|بيشة
103630|نجران
104515|مكة المكرمة
104578|مهد الذهب
104716|ليلى
104923|خليص
105072|خميس مشيط
105299|جازان
105343|جدة
106102|حقل
106281|حائل
106297|حفر الباطن
106667|فيفاء
106744|فرسان
106909|ضبا
107117|ضمد
107304|بريدة
107312|بقيق
107588|بقعاء
107692|بلجرشي
107744|بدر
107781|الزلفي
107797|الظهران
107968|الطائف
108048|السليل
108121|ساجر
108410|الرياض
108435|الرس
108512|عرعر
108617|النماص
108648|القريات
108773|الوجه
108782|عيون الجواء
108841|العلا
108918|القيصومة
108927|القطيف
109101|المبرز
109131|المذنب
109223|المدينة المنورة
109253|الليث
109306|الخرمة
109323|الخبر
109353|الخرج
109380|الخفجي
109391|الخبراء
109417|الجموم
109435|الجبيل
109571|الهفوف
109615|الهياثم
109878|البكيرية
109953|الباحة
109998|العوامية
110060|العقيق
110250|عفيف
110312|الدرعية
110314|الدلم
110325|الدوادمي
110336|الدمام
110619|أبو عريش
110690|أبها
397833|البدائع
399518|المجاردة
409682|ثول
410096|الشفا
11524299|مدينة الملك عبدالله الاقتصادية
11670045|سبت العلايا
11835536|رياض الخبراء
12495725|بارق
12500245|سراة عبيدة
12513572|المشعلية
12513575|حبونا
12546009|رنية
13631408|حوطة بني تميم'''
names={int(row.split('|')[0]):row.split('|')[1]for row in labels.splitlines()}
regions={'02':'الباحة','05':'المدينة المنورة','06':'المنطقة الشرقية','08':'القصيم','10':'الرياض','11':'عسير','13':'حائل','14':'مكة المكرمة','15':'الحدود الشمالية','16':'نجران','17':'جازان','19':'تبوك','20':'الجوف'}
rows=[l.rstrip('\n').split('\t')for l in Path(sys.argv[1]).read_text().splitlines()];result=[]
for r in rows:
 ident=int(r[0])
 if ident not in names:continue
 assert r[8]=='SA'
 region=regions['19'if ident==106102 else '14'if ident==12546009 else r[10]]
 legacy={108410:'riyadh',104515:'makkah',109223:'madinah'}
 result.append({'id':legacy.get(ident,f'sa-{ident}'),'name':names[ident],'region':region,'latitude':float(r[4]),'longitude':float(r[5]),'timeZone':'Asia/Riyadh','countryCode':'SA','sourceID':ident})
result.sort(key=lambda r: (['riyadh','makkah','madinah'].index(r['id']) if r['id'] in ['riyadh','makkah','madinah'] else 3,r['name']))
assert len(result)==len(names) and len(set(x['region']for x in result))==13
(ROOT/'ios/Athar/saudi-cities.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print('Saudi cities:',len(result))
