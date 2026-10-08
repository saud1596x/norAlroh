import SwiftUI
import AuthenticationServices

struct NoorWelcomeView: View {
    let continueWithoutAccount: () -> Void
    @EnvironmentObject private var account: NoorAccountStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    NoorArch().stroke(Theme.gold.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 130, height: 160)
                    NoorRosette().stroke(Theme.gold.opacity(0.22), lineWidth: 1)
                        .frame(width: 76, height: 76)
                    Text("نور").font(.system(size: 30, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.gold)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .accessibilityHidden(true)
                VStack(spacing: 12) {
                    Text("أهلًا بك في نور الروح")
                        .font(.largeTitle.bold()).multilineTextAlignment(.center)
                        .accessibilityIdentifier("welcome.title")
                    Text("ابدأ من حيث توقفت، واقرأ وتدرّب داخل المصحف بهدوء.")
                        .font(.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Label("مصحف مريح للقراءة", systemImage: "book.pages")
                    Label("تسميعك وتسجيلاتك داخل المصحف", systemImage: "mic")
                    Label("وردك وذكرُك في متناولك", systemImage: "sun.horizon")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(24)
        }
        .background(Theme.background.ignoresSafeArea())
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
                    Text("حساب Apple للدخول أو إنشاء الحساب. المزامنة اختيارية من الإعدادات.")
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
                    .buttonStyle(.bordered)
                    .tint(Theme.mint)
                    .disabled(account.busy)
                    .accessibilityIdentifier("welcome.continue")
                Text("القراءة والحفظ متاحان دون حساب، وتبقى بياناتك على جهازك.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .background(Theme.background)
        }
    }

    private var unavailableAccount: some View {
        Text("تسجيل الدخول غير متاح الآن. يمكنك المتابعة وإضافة حسابك لاحقًا من الإعدادات.")
            .font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("welcome.account.unavailable")
    }
}
