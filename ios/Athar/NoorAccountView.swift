import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
#if NOOR_ACCOUNT_ENABLED
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import GoogleSignInSwift
#endif

@MainActor final class NoorAccountStore: ObservableObject {
    @Published private(set) var available = false
    @Published private(set) var signedIn = false
    @Published private(set) var name = ""
    @Published private(set) var busy = false
    @Published var deletionRequested = false
    @Published var message: String?
    private var nonce: String?
    #if NOOR_ACCOUNT_ENABLED
    private var listener: AuthStateDidChangeListenerHandle?
    init() {
        guard let config = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: config),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let scheme = plist["REVERSED_CLIENT_ID"] as? String,
              plist["BUNDLE_ID"] as? String == Bundle.main.bundleIdentifier,
              let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
              types.compactMap({ $0["CFBundleURLSchemes"] as? [String] }).flatMap({ $0 }).contains(scheme) else { return }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        available = true
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.signedIn = user != nil; self?.name = user?.displayName ?? "حسابك" }
        }
    }
    func refresh() async {
        guard available, let user = Auth.auth().currentUser else { return }
        do { try await user.reload(); signedIn = Auth.auth().currentUser != nil }
        catch { message = "تعذّر التحقق من اتصال الحساب. بياناتك المحلية متاحة." }
    }
    func handle(_ url: URL) { guard available else { return }; _ = GIDSignIn.sharedInstance.handle(url) }
    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { message = "تعذّر بدء تسجيل الدخول بأمان."; nonce = nil; return }
        let value = bytes.map { String(format: "%02x", $0) }.joined(); nonce = value
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        guard available, !busy, let rawNonce = nonce else { return }; nonce = nil; busy = true; defer { busy = false }
        do {
            let authorization = try result.get()
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let bytes = apple.identityToken, let token = String(data: bytes, encoding: .utf8) else { throw CocoaError(.coderInvalidValue) }
            let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: rawNonce, fullName: apple.fullName)
            if deletionRequested {
                guard let user = Auth.auth().currentUser, let codeData = apple.authorizationCode, let code = String(data: codeData, encoding: .utf8) else { throw CocoaError(.coderInvalidValue) }
                _ = try await user.reauthenticate(with: credential)
                try await Auth.auth().revokeToken(withAuthorizationCode: code)
                try await deleteUser(user)
            } else { _ = try await Auth.auth().signIn(with: credential) }
        } catch { message = "لم يكتمل الدخول بحساب Apple. حاول مجددًا." }
    }
    func google() async {
        guard available, !busy, let client = FirebaseApp.app()?.options.clientID,
              let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        busy = true; defer { busy = false }
        var presenter = root; while let shown = presenter.presentedViewController { presenter = shown }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: client)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let token = result.user.idToken?.tokenString else { throw CocoaError(.coderInvalidValue) }
            let credential = GoogleAuthProvider.credential(withIDToken: token, accessToken: result.user.accessToken.tokenString)
            if deletionRequested {
                guard let user = Auth.auth().currentUser else { throw CocoaError(.coderInvalidValue) }
                _ = try await user.reauthenticate(with: credential)
                try await deleteUser(user)
            } else { _ = try await Auth.auth().signIn(with: credential) }
        } catch { message = "لم يكتمل الدخول بحساب Google. حاول مجددًا." }
    }
    private func deleteUser(_ user: User) async throws {
        try await Firestore.firestore().collection("users").document(user.uid).collection("private").document("memorization").delete()
        try await user.delete()
        GIDSignIn.sharedInstance.signOut(); signedIn = false; deletionRequested = false; name = ""
        message = "حُذف حسابك ونسخة الحفظ السحابية. بيانات جهازك متاحة دون حساب؛ احذفها من الإعدادات إذا أردت."
    }
    func signOut() {
        guard available, !busy else { return }
        do { try Auth.auth().signOut(); GIDSignIn.sharedInstance.signOut(); signedIn = false; name = "" }
        catch { message = "تعذّر تسجيل الخروج." }
    }
    func backup(memorization: MemorizationStore) async {
        guard available, !busy, let user = Auth.auth().currentUser, memorization.unreadableHistory == nil else { return }
        busy = true; defer { busy = false }
        do {
            let data = try JSONEncoder().encode(MemorizationCloudBackup(version: 1, plan: memorization.plan, archive: .init(version: 1, history: memorization.history, progress: memorization.progress)))
            let compressed = try (data as NSData).compressed(using: .zlib) as Data
            guard compressed.count <= 750_000 else { throw CocoaError(.fileWriteOutOfSpace) }
            try await Firestore.firestore().collection("users").document(user.uid).collection("private").document("memorization").setData(["version": 1, "data": compressed, "updatedAt": FieldValue.serverTimestamp()])
            message = "حُفظت نسخة تقدم الحفظ في حسابك. لا تتضمن صوتك أو تأملاتك."
        } catch { message = "لم تُحفظ النسخة السحابية. تحقق من الاتصال وحاول مجددًا؛ تقدمك المحلي محفوظ." }
    }
    func restore(memorization: MemorizationStore) async {
        guard available, !busy, let user = Auth.auth().currentUser else { return }
        busy = true; defer { busy = false }
        do {
            let document = try await Firestore.firestore().collection("users").document(user.uid).collection("private").document("memorization").getDocument(source: .server)
            guard let compressed = document.data()?["data"] as? Data, compressed.count <= 750_000 else { throw CocoaError(.fileReadCorruptFile) }
            let data = try (compressed as NSData).decompressed(using: .zlib) as Data
            guard data.count <= 10_000_000 else { throw CocoaError(.fileReadCorruptFile) }
            let backup = try JSONDecoder().decode(MemorizationCloudBackup.self, from: data)
            guard Auth.auth().currentUser?.uid == user.uid else { message = "تغيّر الحساب أثناء الاستعادة. لم تتغير بيانات جهازك."; return }
            guard memorization.restore(backup) else { message = memorization.error; return }
            message = "دُمج سجل الحفظ دون تكرار النتائج. بقيت جلستك وخطتك المحلية؛ الاستعادة لا تكمل ورد اليوم."
        } catch { message = "تعذّرت استعادة نسخة صالحة؛ لم تتغير بياناتك المحلية." }
    }
    #else
    init() {}
    func refresh() async {}
    func handle(_ url: URL) {}
    #endif
}
struct MemorizationCloudBackup: Codable {
    let version: Int
    let plan: MemorizationPlan
    let archive: MemorizationArchive
}
struct NoorAccountView: View {
    @EnvironmentObject private var account: NoorAccountStore
    @EnvironmentObject private var memorization: MemorizationStore
    @State private var restoring = false
    @State private var uploading = false
    @State private var deleting = false
    var body: some View {
        Form {
            Section {
                Text("حسابك في نور الروح").font(.title2.bold())
                Text("تسجيل الدخول اختياري. يمكنك حفظ نسخة من خطة الحفظ وتقدمك واستعادتها عند تغيير الجهاز.")
            }
            #if NOOR_ACCOUNT_ENABLED
            if account.available {
                if account.signedIn {
                    Section(account.name) {
                        Button("حفظ نسخة سحابية من تقدمي") { uploading = true }.disabled(account.busy)
                        Button("استعادة نسخة الحفظ") { restoring = true }.disabled(account.busy)
                        Button("حذف حسابي", role: .destructive) { deleting = true }.disabled(account.busy)
                        if account.deletionRequested {
                            Text("أعد تسجيل الدخول بالطريقة المرتبطة بحسابك لتأكيد الحذف.")
                            SignInWithAppleButton(.continue, onRequest: account.prepareApple) { result in Task { await account.completeApple(result) } }.frame(height: 50).disabled(account.busy)
                            GoogleSignInButton { Task { await account.google() } }.frame(height: 50).disabled(account.busy)
                            Button("إلغاء الحذف") { account.deletionRequested = false }
                        }
                        Button("تسجيل الخروج") { account.signOut() }.disabled(account.busy)
                        Text("الحفظ السحابي اختياري؛ لا نرفع التسجيلات الصوتية أو التأملات. بيانات الجهاز تبقى بعد تسجيل الخروج.").font(.caption)
                    }
                } else {
                    Section("تسجيل الدخول") {
                        SignInWithAppleButton(.signIn, onRequest: account.prepareApple) { result in Task { await account.completeApple(result) } }
                            .signInWithAppleButtonStyle(.black).frame(height: 50).disabled(account.busy)
                        GoogleSignInButton { Task { await account.google() } }.frame(height: 50).disabled(account.busy)
                    }
                }
            } else { Section { Text("الدخول بحساب Apple وGoogle قيد التجهيز، ولم يُفعّل على هذه النسخة بعد.") } }
            #else
            Section { Text("الدخول بحساب Apple وGoogle قيد التجهيز، ولم يُفعّل على هذه النسخة بعد.") }
            #endif
            if let message = account.message { Section { Text(message) } }
            Section { Text("تسجيل الدخول بالطريقتين لا يدمج الحسابين تلقائيًا. استخدم الطريقة نفسها لاستعادة نسختك.").font(.caption) }
        }.navigationTitle("حسابي")
            #if NOOR_ACCOUNT_ENABLED
            .confirmationDialog("حذف الحساب ونسخة الحفظ السحابية نهائيًا؟ تبقى بيانات جهازك حتى تحذفها من الإعدادات.", isPresented: $deleting, titleVisibility: .visible) {
                Button("متابعة حذف الحساب", role: .destructive) { account.deletionRequested = true }
            }
            .confirmationDialog("حفظ خطة الحفظ والسجل والإتقان في الحساب المسجّل حاليًا؟ ستُستبدل نسخته السحابية السابقة.", isPresented: $uploading, titleVisibility: .visible) {
                Button("حفظ النسخة") { Task { await account.backup(memorization: memorization) } }
            }
            .confirmationDialog("دمج سجل الحفظ السحابي مع سجل هذا الجهاز؟ تبقى الخطة والجلسة المحلية.", isPresented: $restoring, titleVisibility: .visible) {
                Button("دمج النسخة") { Task { await account.restore(memorization: memorization) } }
            }
            #endif
    }
}
