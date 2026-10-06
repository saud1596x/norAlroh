import SwiftUI
import UniformTypeIdentifiers

struct QuranView: View {
    @EnvironmentObject var store: AtharStore
    @State private var search = ""
    private var filtered: [Surah] {
        let query = normalized(search)
        return store.quran.filter {
            query.isEmpty || normalized($0.name).contains(query)
                || $0.englishName.localizedCaseInsensitiveContains(search) || ArabicSearch.integer(search) == $0.number
        }
    }
    private func normalized(_ value: String) -> String {
        ArabicSearch.normalize(value)
    }
    var body: some View {
        List {
            Section {
                Text("١١٤ سورة. تابع القراءة من آخر صفحة واحفظ علاماتك.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(filtered) { surah in
                NavigationLink { MushafReader(chapter: surah.number) } label: {
                    HStack(spacing: 15) {
                        Text("\(surah.number)").font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.mint).frame(minWidth: 34, minHeight: 44)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(surah.name).font(.title3)
                            Text("\(surah.ayahs.count) آية · \(surah.revelationType == "Meccan" ? "مكية" : "مدنية")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 5)
                }.listRowBackground(Theme.panel).accessibilityIdentifier("surah.\(surah.number)")
            }
            if filtered.isEmpty {
                ContentUnavailableView("لم نجد سورة", systemImage: "magnifyingglass",
                    description: Text("ابحث باسم السورة أو رقمها."))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("القرآن الكريم")
        .toolbar(.visible, for: .tabBar)
        .searchable(text: $search, prompt: "ابحث عن سورة")
    }
}

struct QuranReader: View {
    @EnvironmentObject var store: AtharStore
    let surah: Surah
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("اضغط الآية لإضافة علامة أو إزالتها.").font(.subheadline).foregroundStyle(.secondary)
                if let basmala = QuranText.separateBasmalas[String(surah.number)] {
                    QuranVerseText(basmala, size: 20)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                ForEach(surah.ayahs) { ayah in
                    let bookmarked = store.data.bookmarks.contains("\(surah.number):\(ayah.number)")
                    Button { store.toggleBookmark(surah: surah.number, ayah: ayah.number) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            QuranVerseText(QuranText.verse(chapter: surah.number, ayah: ayah), size: store.data.largeQuran ? 34 : 28)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("الآية \(ayah.number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            if bookmarked {
                                Label("علامة محفوظة", systemImage: "bookmark.fill")
                                    .font(.subheadline).foregroundStyle(Theme.mint)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(bookmarked ? Theme.mint.opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("الآية \(ayah.number). \(QuranText.verse(chapter: surah.number, ayah: ayah))")
                    .accessibilityHint(bookmarked ? "إزالة العلامة" : "حفظ علامة")
                    .accessibilityIdentifier("ayah.\(surah.number).\(ayah.number)")
                    Divider()
                }
                Text("اضغط على الآية لحفظ علامة والعودة إليها لاحقًا.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle(surah.name)
        .sensoryFeedback(.selection, trigger: store.data.bookmarks.count)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.update { $0.largeQuran.toggle() }
                } label: { Image(systemName: "textformat.size").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel(store.data.largeQuran ? "حجم الخط المعتاد" : "تكبير خط القرآن")
            }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: AtharStore
    @State private var text = ""
    @State private var noteToDelete: JournalNote?
    @State private var confirmDelete = false
    @State private var saved = false
    var body: some View {
        List {
            Section("دفتر التأمل") {
                Text("ماذا تريد أن تتذكر من يومك؟ يبقى ما تكتبه على جهازك فقط.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $text).frame(minHeight: 150).accessibilityLabel("اكتب تأملك")
                    .onChange(of: text) { _, value in if value.count > 5000 { text = String(value.prefix(5000)) } }
                Button("احفظ تأملي") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if store.update({ $0.notes.insert(JournalNote(text: trimmed), at: 0) }) {
                        text = ""
                        saved = true
                    }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(store.data.notes) { note in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(note.date, style: .date).font(.subheadline).foregroundStyle(.secondary)
                        Text(note.text).textSelection(.enabled)
                        Button("حذف", role: .destructive) {
                            noteToDelete = note
                            confirmDelete = true
                        }.frame(minHeight: 44)
                    }.padding(.vertical, 8)
                }
            }
            Section("علامات القرآن") {
                if store.data.bookmarks.isEmpty {
                    Text("اضغط آية في القرآن لحفظ علامة.").foregroundStyle(.secondary)
                }
                ForEach(store.data.bookmarks, id: \.self) { key in
                    let numbers = key.split(separator: ":").compactMap { Int($0) }
                    if numbers.count == 2, let surah = store.quran.first(where: { $0.number == numbers[0] }) {
                        NavigationLink { MushafReader(chapter: surah.number, ayah: numbers[1]) } label: {
                            Label("\(surah.name) · الآية \(numbers[1])", systemImage: "bookmark")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("علاماتي وتأملاتي")
        .confirmationDialog("حذف هذا التأمل نهائيًا؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let id = noteToDelete?.id { store.update { $0.notes.removeAll { $0.id == id } } }
                noteToDelete = nil
            }
            Button("إلغاء", role: .cancel) { noteToDelete = nil }
        }
        .alert("حُفظ تأملك على هذا الجهاز", isPresented: $saved) { Button("تم", role: .cancel) {} }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AtharStore
    @EnvironmentObject var notifications: PrayerNotifications
    @EnvironmentObject var dhikrCounters: DhikrCounterStore
    @EnvironmentObject var memorization: MemorizationStore
    @EnvironmentObject var recitation: LocalRecitationRecorder
    @EnvironmentObject var speech: LocalSpeechRecitation
    @EnvironmentObject var friday: FridayStore
    @EnvironmentObject var fridayAlarms: FridayAlarms
    @EnvironmentObject var account: NoorAccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var erase = false
    @State private var exporting = false
    @State private var document = ExportDocument(bytes: Data())
    @State private var exportMessage: String?
    @State private var erasing = false
    var body: some View {
        Form {
            Section("حسابي") {
                NavigationLink("الحساب والنسخة السحابية") { NoorAccountView() }
                NavigationLink("إعدادات يوم الجمعة") { FridaySettingsView() }
            }
            Section("مساحة تحترم خصوصيتك") {
                Text("لا حساب مطلوب، ولا إعلانات أو تتبع. رحلاتك وتأملاتك وعلاماتك وسجلات حفظك محفوظة محليًا.")
                Toggle("تقليل الحركة", isOn: Binding(
                    get: { store.data.lowMotion }, set: { value in store.update { $0.lowMotion = value } }
                ))
                Toggle("خط قرآن أكبر", isOn: Binding(
                    get: { store.data.largeQuran }, set: { value in store.update { $0.largeQuran = value } }
                ))
                Button("تصدير بياناتي") {
                    do {
                        let snapshot = NoorPrivacyExport(device: store.data, adhkarCounters: dhikrCounters.counts, adhkarFavorites: Array(dhikrCounters.favorites).sorted(),
                            memorizationPlan: memorization.plan, memorizationHistory: memorization.history, memorizationSession: memorization.session,
                            prayerPreferences: notifications.preferences, localRecording: try recitation.exportRecording(),
                            lastMushafPage: max(1, min(604, UserDefaults.standard.integer(forKey: "noor.mushaf.lastPage"))),
                            unreadableDeviceData: store.unreadableDeviceData, unreadableMemorizationHistory: memorization.unreadableHistory,
                            memorizationProgress: memorization.progress)
                        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                        document = ExportDocument(bytes: try encoder.encode(snapshot)); exporting = true
                    }
                    catch { exportMessage = "تعذر تجهيز ملف التصدير." }
                }
                Text("ملف التصدير غير مشفر. احفظه في مكان خاص.").font(.subheadline).foregroundStyle(.secondary)
                Button("حذف كل بياناتي", role: .destructive) { erase = true }.disabled(erasing)
                if erasing { ProgressView("حذف البيانات والنموذج المحلي…") }
                NavigationLink("سياسة الخصوصية") { PrivacyView() }.accessibilityIdentifier("settings.privacy")
                NavigationLink("شروط الاستخدام") { NoorLegalDocumentView(documentID: "terms") }.accessibilityIdentifier("settings.terms")
                NavigationLink("الدعم والمساعدة") { NoorLegalDocumentView(documentID: "support") }.accessibilityIdentifier("settings.support")
                NavigationLink("علاماتي") { LibraryView() }.accessibilityIdentifier("settings.library")
                NavigationLink("أدوات الشاشة") { NoorWidgetGuide() }.accessibilityIdentifier("settings.widgets")
                NavigationLink("التراخيص") { SourcesView() }.accessibilityIdentifier("settings.sources")
            }
            Section("عن نور الروح") {
                Text("مصحف كامل، أذكار موثّقة ومواقيت الصلاة. للحفظ تسجيل محلي ومتابعة صوتية اختيارية تقارن الكلمات وتعرض فروقًا محتملة تحتاج مراجعتك.")
                Text("النص القرآني مضمّن في التطبيق. مواقيت الصلاة محسوبة محليًا. لا يقدم نور الروح فتاوى أو تفسيرًا مولدًا.")
                Text("الإصدار \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · البناء \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("الإعدادات")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() } } }
        .confirmationDialog("سيُحذف سجل الرحلات والتأملات والعلامات والحفظ والأذكار والتسجيل والنموذج الصوتي المحلي والإعدادات نهائيًا.", isPresented: $erase, titleVisibility: .visible) {
            Button("حذف كل بياناتي", role: .destructive) {
                Task {
                guard !erasing else { return }
                erasing = true; defer { erasing = false }
                guard await speech.eraseModel() else { exportMessage = speech.message; return }
                guard recitation.erase() else { exportMessage = recitation.message; return }
                if store.erase() {
                    notifications.erasePreferences()
                    dhikrCounters.erase()
                    memorization.erase()
                    friday.erase()
                    fridayAlarms.disable()
                    UserDefaults.standard.removeObject(forKey: "noor.mushaf.lastPage")
                    dismiss()
                }
                }
            }
            Button("إلغاء", role: .cancel) {}
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "noor-alruh-private-data") { result in
            if case .failure = result { exportMessage = "لم يُحفظ الملف. حاول مجددًا واختر مكانًا متاحًا." }
        }
        .alert("بياناتك المحلية", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("تم") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }
}

struct PrivacyView: View {
    var body: some View {
        NoorLegalDocumentView(documentID: "privacy")
    }
}

struct SourcesView: View {
    var body: some View {
        List {
            Section("القرآن الكريم") {
                Text("١١٤ سورة و٦٢٣٦ آية من Tanzil، النص العثماني 1.1 برواية حفص. الآيات منسوخة حرفيًا من المصدر، والبسملة غير المرقمة منفصلة وفق ملف المصدر. الترخيص CC BY 3.0 مع شرط عدم تغيير النص.")
                Link("المصدر وتحديثات النص: Tanzil", destination: URL(string: "https://tanzil.net/")!)
                NavigationLink("نسبة النص وترخيص Tanzil") { BundledLicenseView(title: "ترخيص Tanzil", resource: "Tanzil-LICENSE", extension: "txt") }
                    .accessibilityIdentifier("sources.tanzil")
            }
            Section("صفحات المصحف") {
                Text("٦٠٤ صفحات برواية حفص، بخطوط QCF V2 من Quran Foundation. تُنزّل بيانات المصحف كاملة عند أول فتح، وتُحفظ للقراءة دون اتصال، مع محاولة تحديث كل سبعة أيام. عناوين السور والقراءة المرنة بخط أميري المرخص تحت OFL.")
                Link("مصدر التخطيط والرموز", destination: URL(string: "https://api-docs.quran.foundation/")!)
                NavigationLink("ترخيص بيانات التخطيط والخطوط") { BundledLicenseView(title: "تراخيص المصحف", resource: "QCF-DATA-AND-FONTS-LICENSE", extension: "md") }
                    .accessibilityIdentifier("sources.qcf")
                NavigationLink("ترخيص خط أميري") { BundledLicenseView(title: "ترخيص أميري", resource: "Amiri-OFL", extension: "txt") }
                    .accessibilityIdentifier("sources.amiri")
            }
            Section("الأذكار والتأمل") {
                Text("محتوى حصن المسلم: ١٣٢ بابًا و٢٦٧ نصًا، كما وردت في مصدر hisnmuslim.com. يعرض كل نص الباب ورقمه وعدد التكرار من المصدر. التأملات الشخصية ليست تفسيرًا أو فتوى.")
                Link("المصدر: حصن المسلم", destination: URL(string: "https://www.hisnmuslim.com/")!)
            }
            Section("مدن المملكة") {
                Text("٩٣ مدينة في المناطق الثلاث عشرة. الإحداثيات من GeoNames، والأسماء العربية واختيار المدن من مشروع نور الروح. بيانات المراكز تقريبية.")
                Link("GeoNames · CC BY 4.0", destination: URL(string: "https://www.geonames.org/")!)
                Link("رخصة البيانات", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
            }
            Section("حساب مواقيت الصلاة") {
                Text("Adhan Swift 1.5.0 · Batoul Apps · ترخيص MIT. الحساب يستخدم المدينة وإعدادات المواقيت المحفوظة، مع فاصل عشاء رمضان بحسب تقويم أم القرى.")
                Link("مكتبة Adhan", destination: URL(string: "https://github.com/batoulapps/adhan-swift")!)
                NavigationLink("ترخيص مكتبة حساب الصلاة") { BundledLicenseView(title: "ترخيص Adhan", resource: "ADHAN-SWIFT-LICENSE", extension: "txt") }
                    .accessibilityIdentifier("sources.adhan")
            }
            Section("المتابعة الصوتية المحلية") {
                Text("WhisperKit 1.1.0 · Argmax · MIT. نموذج Whisper متعدد اللغات يُنزّل باختيارك من Hugging Face؛ معالجة الصوت محلية. مقارنة الكلمات لا تعتمد صحة التجويد أو الحفظ، وقد يخطئ التعرّف نفسه.")
                Link("مصدر WhisperKit", destination: URL(string: "https://github.com/argmaxinc/argmax-oss-swift")!)
                NavigationLink("ترخيص WhisperKit") { BundledLicenseView(title: "ترخيص WhisperKit", resource: "WHISPERKIT-LICENSE", extension: "txt") }
                    .accessibilityIdentifier("sources.whisperkit")
                NavigationLink("ترخيص نموذج Whisper") { BundledLicenseView(title: "ترخيص نموذج Whisper", resource: "WHISPER-MODEL-LICENSE", extension: "txt") }
                    .accessibilityIdentifier("sources.whispermodel")
                NavigationLink("تراخيص المكونات التابعة") { BundledLicenseView(title: "مكونات WhisperKit", resource: "WHISPERKIT-THIRD-PARTY", extension: "txt") }
                    .accessibilityIdentifier("sources.whispercomponents")
            }
        }.navigationTitle("التراخيص")
    }
}

struct BundledLicenseView: View {
    let title: String
    let resource: String
    let `extension`: String
    private var notice: String? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: `extension`) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    var body: some View {
        ScrollView {
            if let notice {
                Text(verbatim: notice).font(.footnote).textSelection(.enabled)
                    .accessibilityIdentifier("license.notice")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .environment(\.layoutDirection, .leftToRight)
            } else { ContentUnavailableView("تعذّر فتح الترخيص", systemImage: "doc.text") }
        }.background(Theme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
