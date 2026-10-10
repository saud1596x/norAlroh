import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit

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
        .noorScreenChrome().navigationTitle("القرآن الكريم")
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
        .noorScreenChrome().navigationTitle(surah.name)
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
    var body: some View {
        List {
            Section("علامات القرآن") {
                if store.data.bookmarks.isEmpty {
                    Text("اضغط مطولًا على آية في المصحف، ثم اختر العلامة لحفظها.").foregroundStyle(.secondary)
                }
                ForEach(store.data.bookmarks, id: \.self) { key in
                    let numbers = key.split(separator: ":").compactMap { Int($0) }
                    if numbers.count == 2, let surah = store.quran.first(where: { $0.number == numbers[0] }) {
                        NavigationLink { MushafReader(chapter: surah.number, ayah: numbers[1]) } label: {
                            Label("\(surah.name) · الآية \(numbers[1])", systemImage: "bookmark")
                        }.accessibilityIdentifier("library.bookmark.\(key)")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .noorScreenChrome().navigationTitle("علاماتي")
        .accessibilityIdentifier("library.bookmarks")
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AtharStore
    @EnvironmentObject var notifications: PrayerNotifications
    @EnvironmentObject var prayerLocation: PrayerLocationController
    @EnvironmentObject var dhikrCounters: DhikrCounterStore
    @EnvironmentObject var salawat: NoorSalawatStore
    @EnvironmentObject var memorization: MemorizationStore
    @EnvironmentObject var recitation: LocalRecitationRecorder
    @EnvironmentObject var speech: LegacySpeechArchive
    @EnvironmentObject var retiredFriday: NoorRetiredFridayCleanup
    @EnvironmentObject var account: NoorAccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var erase = false
    @State private var exporting = false
    @State private var document = ExportDocument(bytes: Data())
    @State private var exportMessage: String?
    @State private var erasing = false
    @State private var microphonePermission = AVAudioApplication.shared.recordPermission
    @State private var requestingMicrophone = false
    @State private var eraseRecitation = false
    @State private var erasingRecitation = false
    @State private var recitationRemovalMessage: String?
    @State private var preparingExport = false
    var body: some View {
        Form {
            Section("حسابي") {
                NavigationLink("الحساب والنسخة السحابية") { NoorAccountView() }
            }
            if let message = retiredFriday.message {
                Section {
                    Text(message).foregroundStyle(.secondary)
                    Button("إعادة إلغاء التنبيهات القديمة") { Task { await retiredFriday.cleanup() } }
                        .disabled(retiredFriday.busy)
                }
            }
            Section("القراءة والتذكيرات") {
                NavigationLink("تذكيراتي") { NoorReminderSettings() }.accessibilityIdentifier("settings.reminders")
                NavigationLink("حماية وقت الورد") { NoorFocusView() }
            }
            Section("الميكروفون والتسميع") {
                Text(microphonePermission == .granted ? "الميكروفون مسموح" : microphonePermission == .denied ? "إذن الميكروفون مرفوض" : "لم يُطلب إذن الميكروفون بعد")
                    .accessibilityIdentifier("settings.microphone.status")
                if microphonePermission == .undetermined {
                    Button("السماح بالميكروفون") {
                        Task { @MainActor in
                            guard !requestingMicrophone else { return }
                            requestingMicrophone = true
                            _ = await AVAudioApplication.requestRecordPermission()
                            microphonePermission = AVAudioApplication.shared.recordPermission
                            requestingMicrophone = false
                        }
                    }.disabled(requestingMicrophone)
                    .accessibilityIdentifier("settings.microphone.request")
                } else {
                    Button("فتح إعدادات الميكروفون") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.accessibilityIdentifier("settings.microphone.open")
                }
                Text("يُستخدم الميكروفون عند بدء التسميع. السماح به لا يضمن دقة التعرّف على القراءة.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("حذف تسجيلات وسجلات التسميع", role: .destructive) { eraseRecitation = true }
                    .disabled(erasingRecitation || erasing || preparingExport).accessibilityIdentifier("settings.recitation.erase")
                if erasingRecitation { ProgressView("حذف تسجيلات التسميع…") }
                if let recitationRemovalMessage { Text(recitationRemovalMessage).font(.footnote).accessibilityIdentifier(recitationRemovalMessage == "حُذفت تسجيلات وسجلات التسميع." ? "settings.recitation.erased" : "settings.recitation.eraseError") }
            }
            Section("مساحة تحترم خصوصيتك") {
                Text(account.available
                     ? "الحساب اختياري، ولا إعلانات أو تتبع. بياناتك محفوظة على جهازك؛ لا تُرفع بيانات تقدمك إلا باختيارك من صفحة الحساب. المزامنة لا تتضمن التسجيلات والتأملات والموقع."
                     : "لا حساب مطلوب، ولا إعلانات أو تتبع. رحلاتك وتأملاتك وعلاماتك وسجلات حفظك محفوظة محليًا.")
                Toggle("تقليل الحركة", isOn: Binding(
                    get: { store.data.lowMotion }, set: { value in store.update { $0.lowMotion = value } }
                ))
                Toggle("خط قرآن أكبر", isOn: Binding(
                    get: { store.data.largeQuran }, set: { value in store.update { $0.largeQuran = value } }
                ))
                Button("تصدير بياناتي") {
                    Task { @MainActor in
                    guard !preparingExport, !erasing, !erasingRecitation else { return }
                    preparingExport = true; exportMessage = nil; defer { preparingExport = false }
                    do {
                        let recording = try await recitation.exportRecordingAsync()
                        let recordingMetadata = try await Task.detached(priority: .userInitiated) {
                            try MushafRecordingArchive.exportMetadata()
                        }.value
                        let snapshot = NoorPrivacyExport(device: store.data, adhkarCounters: dhikrCounters.counts, adhkarFavorites: Array(dhikrCounters.favorites).sorted(),
                            memorizationPlan: memorization.plan, memorizationHistory: memorization.history, memorizationSession: memorization.session,
                            prayerPreferences: notifications.preferences, localRecording: recording,
                            lastMushafPage: max(1, min(604, UserDefaults.standard.integer(forKey: "noor.mushaf.lastPage"))),
                            unreadableDeviceData: store.unreadableDeviceData, unreadableMemorizationHistory: memorization.unreadableHistory,
                            memorizationProgress: memorization.progress, memorizationPractice: memorization.practice,
                            unreadableMemorizationPractice: memorization.unreadablePractice, speechPosition: speech.savedPosition,
                            unreadableSpeechPosition: speech.unreadablePosition, previousSpeechPosition: speech.previousPosition, preCloudMerge: memorization.preCloudMerge, syncJournal: NoorReadingSyncJournal.shared.exportBytes, preReadingMerge: UserDefaults.standard.data(forKey: "noor.sync.preReadingMerge"), khatmahArchive: KhatmahStore.shared.exportBytes, mushafStudy: memorization.mushafStudy, unreadableMushafStudy: memorization.unreadableMushafStudy, mushafRecordings: recordingMetadata, salawatArchive: salawat.exportBytes, personalReminderArchive: notifications.personalExport)
                        let bytes = try await Task.detached(priority: .userInitiated) {
                            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                            return try encoder.encode(snapshot)
                        }.value
                        document = ExportDocument(bytes: bytes); exporting = true
                    }
                    catch { exportMessage = "تعذر تجهيز ملف التصدير." }
                    }
                }
                .disabled(preparingExport || erasing || erasingRecitation)
                if preparingExport { ProgressView("تجهيز ملف التصدير…") }
                Text("ملف التصدير غير مشفر. احفظه في مكان خاص. يمكن حذف ملفات التسميع من قسم الميكروفون والتسميع.").font(.subheadline).foregroundStyle(.secondary)
                Button("حذف كل بياناتي", role: .destructive) { erase = true }.disabled(erasing || erasingRecitation || preparingExport)
                if erasing { ProgressView("حذف البيانات والنموذج المحلي…") }
                NavigationLink("سياسة الخصوصية") { PrivacyView() }.accessibilityIdentifier("settings.privacy")
                NavigationLink("شروط الاستخدام") { NoorLegalDocumentView(documentID: "terms") }.accessibilityIdentifier("settings.terms")
                NavigationLink("الدعم والمساعدة") { NoorLegalDocumentView(documentID: "support") }.accessibilityIdentifier("settings.support")
                NavigationLink("علاماتي") { LibraryView() }.accessibilityIdentifier("settings.library")
                NavigationLink("التنزيلات") { NoorAudioDownloadsView() }.accessibilityIdentifier("settings.downloads")
                NavigationLink("أدوات الشاشة") { NoorWidgetGuide() }.accessibilityIdentifier("settings.widgets")
            }
            Section("عن نور الروح") {
                Text("مصحف كامل، وأذكار ومواقيت الصلاة. التسميع يحاول تحديد موضع التلاوة داخل المصحف، وقد يتعذّر التتبع. لا يقيس صحة النطق أو التجويد. يمكن حذف الصوت وبيانات التسميع المحلية من الإعدادات.")
                    .accessibilityIdentifier("settings.studyCapability")
                Text("النص القرآني مضمّن في التطبيق. مواقيت الصلاة محسوبة محليًا. لا يقدم نور الروح فتاوى أو تفسيرًا مولدًا.")
                Text("الإصدار \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · البناء \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .noorScreenChrome().navigationTitle("الإعدادات")
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            microphonePermission = AVAudioApplication.shared.recordPermission
        }
        .confirmationDialog("حذف تسجيلات وسجلات التسميع نهائيًا؟ تبقى بيانات الحفظ والعلامات والحساب.", isPresented: $eraseRecitation, titleVisibility: .visible) {
            Button("حذف تسجيلات التسميع", role: .destructive) {
                Task { @MainActor in
                    guard !erasingRecitation, !erasing, !preparingExport else { return }
                    erasingRecitation = true
                    defer { erasingRecitation = false }
                    guard recitation.erase() else { recitationRemovalMessage = recitation.message; return }
                    do {
                        try await Task.detached(priority: .userInitiated) { try MushafRecordingArchive.erase() }.value
                        speech.eraseSavedPosition()
                        recitationRemovalMessage = "حُذفت تسجيلات وسجلات التسميع."
                    } catch { recitationRemovalMessage = "تعذّر إكمال حذف التسجيلات. أعد المحاولة بعد فتح قفل الجهاز." }
                }
            }
            Button("إلغاء", role: .cancel) {}
        }
        // Pulling a long settings list must not dismiss the entire sheet.
        // Users can still leave explicitly with the Done button.
        .interactiveDismissDisabled()
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() } } }
        .confirmationDialog("سيُحذف سجل الرحلات والتأملات والعلامات والحفظ والأذكار والتسجيل والنموذج الصوتي المحلي والإعدادات المحلية نهائيًا وتتوقف المزامنة. تبقى بيانات حسابك السحابية حتى تحذف الحساب.", isPresented: $erase, titleVisibility: .visible) {
            Button("حذف كل بياناتي", role: .destructive) {
                Task {
                guard !erasing, !erasingRecitation, !preparingExport else { return }
                erasing = true; defer { erasing = false }
                account.disconnectLocalSync()
                guard await speech.eraseModel() else { exportMessage = speech.message; return }
                guard await NoorAudioDownloads.shared.erase() else { exportMessage = NoorAudioDownloads.shared.message; return }
                guard recitation.erase() else { exportMessage = recitation.message; return }
                guard NoorFocusController.shared.erase() else { exportMessage = NoorFocusController.shared.message ?? "تعذّر مسح إعدادات حماية الورد."; return }
                guard await KhatmahStore.shared.erase() else { exportMessage = KhatmahStore.shared.error; return }
                guard salawat.erase() else { exportMessage = salawat.error; return }
                do { try await Task.detached(priority: .userInitiated) { try MushafRecordingArchive.erase() }.value }
                catch { exportMessage = "تعذّر حذف تسجيلات التسميع. حاول بعد فتح قفل الجهاز."; return }
                if store.erase() {
                    notifications.erasePreferences()
                    prayerLocation.erase()
                    dhikrCounters.erase()
                    memorization.erase()
                    speech.eraseSavedPosition()
                    await retiredFriday.cleanup()
                    retiredFriday.eraseArchivedRecords()
                    UserDefaults.standard.removeObject(forKey: "noor.mushaf.lastPage")
                    NoorReadingSyncJournal.shared.erase()
                    UserDefaults.standard.removeObject(forKey: "noor.sync.preReadingMerge")
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
