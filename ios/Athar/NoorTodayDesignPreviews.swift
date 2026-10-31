import SwiftUI
import WidgetKit

// Static design fixtures only, using the actual production components. These
// previews are not screenshots of an installed widget or live prayer evidence.
private struct NoorTodayDesignPreview: View {
    let composition: NoorDuaComposition
    @Environment(\.colorScheme) private var scheme
    private var tokens: NoorChromeTokens { .init(scheme: scheme) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoorChromeTokens.Space.section) {
                NoorTodayComposition(greeting: "صباحك نور وسكينة", dateText: "السبت · 20 جمادى الأولى",
                    readingTitle: "وردك اليوم", readingDetail: "20 صفحة · 1–20", readingStatus: nil,
                    composition: composition) {
                        Label("أكمل ختمتك", systemImage: "arrow.left")
                    } accountAction: {
                        Label("حسابي", systemImage: "person.crop.circle").font(.subheadline).frame(minHeight: 44)
                    } prayerAction: {
                        NoorTodayRouteLabel(title: "الصلاة القادمة", subtitle: "الوقت من موقعك المؤكد", symbol: "sun.horizon")
                    }
                NoorDuaWidgetComposition(dua: NoorDuaCatalog.home[9], family: .systemMedium, composition: composition)
                    .padding(16).frame(height: 180)
                    .background(tokens.surface, in: RoundedRectangle(cornerRadius: 16))
            }.padding(24)
        }.background(tokens.background)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar_SA"))
    }
}

struct NoorTodayDesignPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            NoorTodayDesignPreview(composition: .linear).previewDisplayName("اليوم + دعاء · خطي")
            NoorTodayDesignPreview(composition: .editorial).previewDisplayName("اليوم + دعاء · تحريري")
            NoorTodayDesignPreview(composition: .najdi).previewDisplayName("اليوم + دعاء · نجدي — المعتمد")
            NoorTodayDesignPreview(composition: .najdi).preferredColorScheme(.dark).previewDisplayName("نجدي · داكن")
            NoorTodayDesignPreview(composition: .najdi).environment(\.dynamicTypeSize, .accessibility2)
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
