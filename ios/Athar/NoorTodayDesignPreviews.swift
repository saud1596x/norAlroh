import SwiftUI
import WidgetKit

#if DEBUG || NOOR_ACCEPTANCE_TESTING
// Static design data using the production components. This is neither an
// installed widget nor live prayer or saved-progress evidence.
struct NoorTodayDesignFixture: View {
    enum Surface { case combined, today, mediumDua }
    let composition: NoorDuaComposition
    var surface: Surface = .combined
    @Environment(\.colorScheme) private var scheme
    private var tokens: NoorChromeTokens { .init(scheme: scheme) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoorChromeTokens.Space.section) {
                if surface != .mediumDua { today }
                if surface != .today { mediumDua }
            }.padding(24)
        }.background(tokens.background)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar_SA"))
    }
    private var today: some View {
        NoorTodayComposition(greeting: "صباحك نور وسكينة", dateText: "السبت · 20 جمادى الأولى",
            readingTitle: "وردك اليوم", readingDetail: "20 صفحة · 1–20", readingStatus: nil,
            composition: composition) {
                Label("أكمل ختمتك", systemImage: "arrow.left")
                    .accessibilityIdentifier("design.reading.action")
            } accountAction: {
                Label("حسابي", systemImage: "person.crop.circle").font(.subheadline).frame(minHeight: 44)
                    .accessibilityIdentifier("design.account")
            } prayerAction: {
                NoorTodayRouteLabel(title: "مواقيت الصلاة", subtitle: "اختر مدينتك لعرض الوقت الصحيح", symbol: "location")
                    .accessibilityElement(children: .combine).accessibilityIdentifier("design.prayer")
            }
    }
    private var mediumDua: some View {
        NoorDuaWidgetComposition(dua: NoorDuaCatalog.home[9], family: .systemMedium, composition: composition)
            .padding(16).frame(height: 180)
            .background(scheme == .dark ? NoorWidgetPalette.ink : NoorWidgetPalette.ivory,
                        in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("design.mediumDua")
            #if NOOR_ACCEPTANCE_TESTING
            .overlayPreferenceValue(NoorDuaDesignBoundsKey.self) { anchors in
                GeometryReader { geometry in
                    if let text = anchors["text"], let component = anchors["component"] {
                        let textRect = geometry[text], componentRect = geometry[component]
                        let cardRect = CGRect(origin: .zero, size: geometry.size)
                        Color.clear.accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("design.dua.geometry")
                            .accessibilityLabel("Native dua layout bounds")
                            .accessibilityValue("textFits=\(componentRect.insetBy(dx: -0.5, dy: -0.5).contains(textRect));componentFits=\(cardRect.insetBy(dx: -0.5, dy: -0.5).contains(componentRect));textHeight=\(textRect.height);componentHeight=\(componentRect.height);cardHeight=\(cardRect.height)")
                            .frame(width: 1, height: 1).allowsHitTesting(false)
                    }
                }
            }
            #endif
    }
}

struct NoorTodayDesignPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            NoorTodayDesignFixture(composition: .linear).previewDisplayName("اليوم + دعاء · خطي")
            NoorTodayDesignFixture(composition: .editorial).previewDisplayName("اليوم + دعاء · تحريري")
            NoorTodayDesignFixture(composition: .najdi).previewDisplayName("اليوم + دعاء · نجدي — المعتمد")
            NoorTodayDesignFixture(composition: .najdi).preferredColorScheme(.dark).previewDisplayName("نجدي · داكن")
            NoorTodayDesignFixture(composition: .najdi).environment(\.dynamicTypeSize, .accessibility3)
                .previewDisplayName("نجدي · خط مكبر")
        }
    }
}

struct NoorDuaCompositionPreviews: PreviewProvider {
    private static func widget(_ composition: NoorDuaComposition) -> some View {
        NoorDuaWidgetComposition(dua: NoorDuaCatalog.home[9], family: .systemMedium, composition: composition)
            .containerBackground(NoorWidgetPalette.ivory, for: .widget)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar_SA"))
            .preferredColorScheme(.light)
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
    static var previews: some View {
        Group {
            widget(.linear).previewDisplayName("دعاء متوسط · خطي")
            widget(.editorial).previewDisplayName("دعاء متوسط · تحريري")
            widget(.najdi).previewDisplayName("دعاء متوسط · نجدي — المعتمد")
        }
    }
}
#endif

#if NOOR_ACCEPTANCE_TESTING
struct NoorAcceptanceDesignRequest {
    let name: String
    let composition: NoorDuaComposition?
    let scheme: ColorScheme
    let typeSize: DynamicTypeSize
    let surface: NoorTodayDesignFixture.Surface
    static var current: Self? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-NoorAcceptanceDesignCase"), args.indices.contains(index + 1) else { return nil }
        let name = args[index + 1]
        let cases: [String: (NoorDuaComposition?, ColorScheme, DynamicTypeSize)] = [
            "linear-light": (.linear, .light, .large), "editorial-light": (.editorial, .light, .large),
            "najdi-light": (.najdi, .light, .large), "najdi-dark": (.najdi, .dark, .large),
            "najdi-ax": (.najdi, .light, .accessibility3),
            "production-light": (nil, .light, .large), "production-dark": (nil, .dark, .large),
            "production-ax": (nil, .light, .accessibility3)]
        guard let value = cases[name] else { return nil }
        return .init(name: name, composition: value.0, scheme: value.1, typeSize: value.2,
                     surface: args.contains("-NoorAcceptanceDesignMediumDua") ? .mediumDua : .today)
    }
}

struct NoorAcceptanceDesignHost: View {
    let request: NoorAcceptanceDesignRequest
    var body: some View {
        Group {
            if let composition = request.composition {
                NoorTodayDesignFixture(composition: composition, surface: request.surface)
            } else {
                // Real stores and navigation: only display traits vary.
                RootView()
            }
        }
        .overlay(alignment: .topLeading) { NoorAcceptanceDesignTraits() }
        .environment(\.colorScheme, request.scheme)
        .preferredColorScheme(request.scheme)
        .environment(\.dynamicTypeSize, request.typeSize)
        .onAppear {
            print("NOOR_DESIGN_CAPTURE \(request.composition == nil ? "PRODUCTION_TODAY_REAL_STATE" : "SYNTHETIC_DESIGN_DATA") case=\(request.name) scheme=\(request.scheme) typeSize=\(request.typeSize)")
        }
    }
}

private struct NoorAcceptanceDesignTraits: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    var body: some View {
        Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("design.actualTraits")
            .accessibilityLabel("Native design display traits")
            .accessibilityValue("scheme=\(scheme == .dark ? "dark" : "light");accessibility=\(typeSize.isAccessibilitySize);rtl=\(direction == .rightToLeft)")
    }
}
#endif
