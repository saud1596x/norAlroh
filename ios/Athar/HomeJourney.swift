import SwiftUI
import Combine

struct ConstellationView: View {
    let journeys: [JourneyRecord]
    private let points: [CGPoint] = [
        .init(x: 0.60, y: 0.35), .init(x: 0.78, y: 0.68), .init(x: 0.45, y: 0.76),
        .init(x: 0.26, y: 0.46), .init(x: 0.10, y: 0.75), .init(x: 0.37, y: 0.10), .init(x: 0.90, y: 0.17)
    ]
    var body: some View {
        Canvas { context, size in
            let locations = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            let edges = [(0, 1), (0, 2), (2, 3), (3, 4), (3, 5), (0, 5), (0, 6)]
            for (index, edge) in edges.enumerated() {
                var path = Path()
                path.move(to: locations[edge.0])
                path.addLine(to: locations[edge.1])
                context.stroke(path, with: .color(Theme.mint.opacity(index < journeys.count ? 0.75 : 0.22)),
                    style: StrokeStyle(lineWidth: 1, dash: index < journeys.count ? [] : [3, 5]))
            }
            for (index, point) in locations.enumerated() {
                let active = index < journeys.count
                let glow = Path(ellipseIn: CGRect(x: point.x - 19, y: point.y - 19, width: 38, height: 38))
                context.fill(glow, with: .color(Theme.mint.opacity(active ? 0.12 : 0.03)))
                let radius: CGFloat = active ? 5 : 3
                let node = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
                context.fill(node, with: .color(Theme.mint.opacity(active ? 1 : 0.4)))
            }
        }
        .frame(height: 185)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("كوكبتك الشخصية، \(journeys.count) رحلة محفوظة. أول سبع رحلات تنير عقد الخريطة.")
    }
}

struct HomeView: View {
    @EnvironmentObject var store: AtharStore
    @State private var minutes = 7
    @State private var mood = Mood.calm
    @State private var journey = false
    @State private var focus = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("وقت قليل، وأثر جميل").font(.subheadline).foregroundStyle(Theme.mint)
                Text("مساحة لك، وسط زحام يومك.").font(.largeTitle.bold())
                Text("خذ لحظة لنفسك، ودع خطواتك الصغيرة تضيء كوكبتك.")
                    .foregroundStyle(.secondary)
                Card {
                    HStack {
                        Text("كوكبتك تبدأ بلحظة").font(.title2.bold())
                        Spacer()
                        Label("\(store.data.journeys.count)", systemImage: "sparkle").foregroundStyle(Theme.mint)
                    }
                    ConstellationView(journeys: store.data.journeys)
                    Text("لا سباق. لا مقارنة. فقط أثرك الخاص.").font(.subheadline).foregroundStyle(.secondary)
                }
                Card {
                    Text("كيف يبدو عالمك اليوم؟").font(.title2.bold())
                    Picker("الوقت المتاح", selection: $minutes) {
                        ForEach([3, 7, 12], id: \.self) { Text("\($0) دقائق").tag($0) }
                    }.pickerStyle(.segmented)
                    VStack(spacing: 10) {
                        ForEach(Mood.allCases) { value in
                            Button { mood = value } label: {
                                HStack {
                                    Label(value.title, systemImage: value.symbol)
                                    Spacer()
                                    if mood == value { Image(systemName: "checkmark.circle.fill") }
                                }
                                .padding(14)
                                .frame(minHeight: 48)
                                .background(mood == value ? Theme.mint.opacity(0.16) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(mood == value ? Theme.mint : Color.primary)
                            .accessibilityAddTraits(mood == value ? [.isSelected] : [])
                        }
                    }
                    Text("آية، ذكر، تأمل، وخطوة خير. رحلة مقترحة تناسب وقتك.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    PrimaryButton(title: "ابدأ رحلتي") { journey = true }
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if let next = PrayerCalculator.next(data: store.data, now: context.date) {
                        Card {
                            Label("الصلاة القادمة", systemImage: "clock").foregroundStyle(.secondary)
                            HStack {
                                Text(next.name).font(.title2.bold())
                                Spacer()
                                Text(PrayerCalculator.time(next.date, city: store.data.city)).font(.title2.monospacedDigit())
                                    .environment(\.layoutDirection, .leftToRight)
                            }.foregroundStyle(Theme.mint)
                            Text("\(store.data.city.name) · غيّر المدينة في قسم الصلاة لتناسب موقعك.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Button { focus = true } label: {
                    Card {
                        Label("دقيقة حضور", systemImage: "leaf").font(.headline)
                        Text("استراحة هادئة، على مهل.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle("أثر")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $journey) {
            NavigationStack { JourneyView(mood: mood, minutes: minutes) }
        }
        .sheet(isPresented: $focus) { NavigationStack { FocusView() } }
    }
}

struct JourneyView: View {
    @EnvironmentObject var store: AtharStore
    @Environment(\.dismiss) private var dismiss
    let mood: Mood
    let minutes: Int
    @State private var step = 0
    @State private var count = 0
    @State private var note = ""
    @State private var confirmClose = false
    @State private var showSurah = false
    @State private var counterFeedback = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProgressView(value: Double(step + 1), total: 4)
                    .accessibilityLabel("الخطوة \(step + 1) من أربع")
                Text("\(step + 1) من ٤ · نحو \(minutes) دقائق للرحلة").font(.subheadline).foregroundStyle(Theme.mint)
                switch step {
                case 0:
                    Text("وقفة مع آية").font(.largeTitle.bold())
                    if let surah = store.quran.first(where: { $0.number == mood.reference.surah }),
                       let ayah = surah.ayahs.first(where: { $0.number == mood.reference.ayah }) {
                        QuranVerseText(ayah.text)
                        Text("\(surah.name) · الآية \(ayah.number)").foregroundStyle(.secondary)
                        Button("اقرأ السورة كاملة") { showSurah = true }
                    } else {
                        Text("النص القرآني غير متاح في هذه النسخة.").foregroundStyle(.secondary)
                    }
                    Text("اقرأ على مهل. هذه وقفة شخصية مع النص وليست تفسيرًا.").foregroundStyle(.secondary)
                case 1:
                    Text(mood.dhikr).font(.largeTitle.bold()).frame(maxWidth: .infinity)
                    Button {
                        count += 1
                        counterFeedback += 1
                    } label: {
                        VStack(spacing: 12) {
                            Text("\(count)").font(.largeTitle.monospacedDigit())
                            Text("اضغط للعدّ").font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 155)
                        .background(Theme.mint.opacity(0.15), in: RoundedRectangle(cornerRadius: 40))
                    }
                    .sensoryFeedback(.selection, trigger: counterFeedback)
                    .accessibilityLabel("إضافة ذكر. العداد الحالي \(count)")
                    Text("عدّ اختياري مقترح: \(minutes == 3 ? 5 : minutes == 7 ? 10 : 20). العدد لتنظيم الجلسة وليس سنة محددة.")
                        .foregroundStyle(.secondary)
                case 2:
                    Text("بصوتك أنت").font(.largeTitle.bold())
                    Text(mood.question)
                    TextEditor(text: $note).frame(minHeight: 180)
                        .padding(10).scrollContentBackground(.hidden)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("تأملك الخاص")
                        .onChange(of: note) { _, value in
                            if value.count > 5000 { note = String(value.prefix(5000)) }
                        }
                    Label("سيُحفظ على جهازك عند إتمام الرحلة. يمكنك المتابعة دون كتابة.", systemImage: "lock")
                        .font(.subheadline).foregroundStyle(.secondary)
                default:
                    Text("خطوة صغيرة، خارج الشاشة.").font(.largeTitle.bold())
                    Text(mood.action).font(.title2).lineSpacing(10)
                    Text("احفظ الرحلة واتخذ الخطوة عندما يناسبك. حفظ الرحلة لا يعني أنك أنجزت العمل المقترح.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if step > 0 { Button("السابق") { step -= 1 }.frame(minHeight: 44) }
                    Spacer()
                }
                PrimaryButton(title: step < 3 ? "تابع الرحلة" : "احفظ أثري") {
                    if step < 3 { step += 1 }
                    else if store.finish(mood: mood, minutes: minutes, note: note) { dismiss() }
                }
            }.padding(24)
        }
        .background(Theme.background)
        .navigationTitle(mood.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("إغلاق") { confirmClose = true }.frame(minHeight: 44)
            }
        }
        .interactiveDismissDisabled()
        .confirmationDialog("لن تُحفظ هذه الرحلة إذا أغلقتها الآن.", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("إنهاء الرحلة دون حفظ", role: .destructive) { dismiss() }
            Button("متابعة الرحلة", role: .cancel) {}
        }
        .sheet(isPresented: $showSurah) {
            NavigationStack {
                if let surah = store.quran.first(where: { $0.number == mood.reference.surah }) {
                    QuranReader(surah: surah).toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("تم") { showSurah = false } }
                    }
                }
            }
        }
    }
}

struct FocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var remaining = 60
    @State private var running = false
    @State private var deadline = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            Text("كن هنا، للحظة.").font(.largeTitle.bold())
            Text("استراحة عامة للهدوء. تنفّس بصورة طبيعية، دون ممارسة تعبدية مخصوصة.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("\(remaining)").font(.system(.largeTitle, design: .rounded).monospacedDigit())
                .frame(width: 160, height: 160)
                .background(Theme.mint.opacity(0.15), in: Circle())
                .accessibilityLabel("الوقت المتبقي \(remaining) ثانية")
            PrimaryButton(title: remaining == 0 ? "ابدأ مجددًا" : running ? "إيقاف مؤقت" : "ابدأ الدقيقة", icon: "timer") {
                if remaining == 0 { remaining = 60 }
                running.toggle()
                if running { deadline = Date().addingTimeInterval(TimeInterval(remaining)) }
            }
            Spacer()
        }.padding(24)
        .background(Theme.background)
        .navigationTitle("دقيقة حضور")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() } } }
        .onReceive(timer) { now in
            guard running else { return }
            remaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
            if remaining == 0 { running = false }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { running = false } }
    }
}
