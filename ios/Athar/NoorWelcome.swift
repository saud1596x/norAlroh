import SwiftUI
import AuthenticationServices

struct NoorWelcomeView: View {
    let continueWithoutAccount: () -> Void
    @EnvironmentObject private var account: NoorAccountStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ZStack {
                    NoorSanctuaryScene(compact: false)
                    VStack(spacing: 10) {
                        Text("نور الروح").font(.largeTitle.bold()).foregroundStyle(Theme.gold)
                        Text("قرآنٌ، وذكرٌ، وسكينة").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 70)
                }
                .frame(maxWidth: .infinity)
                .frame(height: typeSize.isAccessibilitySize ? 170 : 240)
                .clipped()
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    Text("على مهل،\nاقترب كل يوم.")
                        .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("welcome.title")
                    Text("مساحتك لوردٍ من القرآن، وذكرٍ يرافق يومك. ابدأ بخطوة تناسبك، وعد إلى موضعك متى شئت.")
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 20) {
                    welcomeFeature("من حيث توقفت", detail: "ارجع إلى صفحتك وواصل وردك.", symbol: "bookmark")
                    Rectangle().fill(Theme.gold.opacity(0.16)).frame(height: 1).accessibilityHidden(true)
                    welcomeFeature("ذكرٌ يرافق يومك", detail: "أذكار الصباح والمساء، مع عدّاد محفوظ.", symbol: "sun.horizon")
                }
                .padding(22).background(Theme.panel, in: RoundedRectangle(cornerRadius: 24))
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                #if NOOR_ACCOUNT_ENABLED
                if account.available {
                    SignInWithAppleButton(.continue, onRequest: account.prepareApple) { result in
                        Task { await account.completeApple(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .disabled(account.busy)
                    .accessibilityIdentifier("welcome.apple")
                    Text("حساب Apple للدخول والمزامنة الاختيارية بين أجهزتك.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else { unavailableAccount }
                #else
                unavailableAccount
                #endif
                if account.busy { ProgressView("جارٍ إكمال الدخول") }
                if let message = account.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("welcome.account.message")
                }
                Button("المتابعة دون حساب", action: continueWithoutAccount)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.mint)
                    .disabled(account.busy)
                    .accessibilityIdentifier("welcome.continue")
                Text("الدخول اختياري. ابدأ القراءة والأذكار دون حساب.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
        }
    }

    private func welcomeFeature(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Theme.gold)
                .frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }

    private var unavailableAccount: some View {
        Text("تسجيل الدخول غير متاح الآن. يمكنك المتابعة وإضافة حسابك لاحقًا من الإعدادات.")
            .font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("welcome.account.unavailable")
    }
}
