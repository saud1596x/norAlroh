import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import Network
#if NOOR_ACCOUNT_ENABLED
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
#endif

@MainActor final class NoorAccountStore: ObservableObject {
    @Published private(set) var available = false
    @Published private(set) var signedIn = false
    @Published private(set) var name = ""
    @Published private(set) var busy = false
    @Published var deletionRequested = false
    @Published var message: String?
    @Published private(set) var uid: String?
    @Published private(set) var syncing = false
    @Published private(set) var syncStatus = "المزامنة متوقفة."
    private weak var syncStore: AtharStore?
    private weak var syncMemorization: MemorizationStore?
    private var syncTask: Task<Void, Never>?
    private var syncGeneration = UUID()
    private var pendingSync = false
    private var foreground = true
    private var applyingSync = false
    private var deferredPlan: MemorizationPlan?
    private var observedMemorization: Data?
    private let connection = NWPathMonitor()
    private var nonce: String?
    func attach(store: AtharStore, memorization: MemorizationStore) {
        foreground = true; syncStore = store; syncMemorization = memorization
        captureLocalChanges(); scheduleSync()
    }
    private func localBackup(_ memorization: MemorizationStore) -> MemorizationCloudBackup {
        .init(version: 1, plan: memorization.plan,
              archive: .init(version: 1, history: memorization.history, progress: memorization.progress, plan: memorization.plan))
    }
    private func fingerprint(_ memorization: MemorizationStore) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(localBackup(memorization))
    }
    func captureLocalChanges(planChanged: Bool = false, memoryChanged: Bool = false) {
        guard !applyingSync, let store = syncStore, let memorization = syncMemorization,
              store.unreadableDeviceData == nil, memorization.unreadableHistory == nil else { return }
        let journal = NoorReadingSyncJournal.shared
        let page = UserDefaults.standard.object(forKey: "noor.mushaf.lastPage") == nil ? nil
            : max(1, min(604, UserDefaults.standard.integer(forKey: "noor.mushaf.lastPage")))
        if planChanged { deferredPlan = nil }
        else if let plan = deferredPlan, memorization.session == nil, memorization.practice == nil {
            if memorization.applySyncedPlan(plan) { deferredPlan = nil }
        }
        let changed = journal.capture(data: store.data, page: page, plan: planChanged ? memorization.plan : nil)
        var changedMemory = false
        if memoryChanged || planChanged || observedMemorization == nil {
            let next = fingerprint(memorization)
            changedMemory = next != observedMemorization; observedMemorization = next
        }
        if changed || changedMemory { scheduleSync() }
    }
    private func bindLocalData(owner: String) -> Bool {
        guard let store = syncStore, store.unreadableDeviceData == nil else { return false }
        let journal = NoorReadingSyncJournal.shared
        if let bound = journal.record?.owner {
            guard bound == owner else { message = "بيانات الجهاز مرتبطة بحساب آخر؛ لم تُنقل إلى هذا الحساب."; return false }
            return journal.unreadable == nil
        }
        guard journal.setEnabled(false, owner: owner, data: store.data, page: nil, plan: nil) else {
            message = journal.error; return false
        }
        return true
    }
    func setSyncEnabled(_ enabled: Bool) {
        guard let uid, let store = syncStore, let memorization = syncMemorization else { return }
        let journal = NoorReadingSyncJournal.shared
        let page = UserDefaults.standard.object(forKey: "noor.mushaf.lastPage") == nil ? nil
            : max(1, min(604, UserDefaults.standard.integer(forKey: "noor.mushaf.lastPage")))
        let existingPlan = UserDefaults.standard.data(forKey: "noor.memorization.plan") != nil || !memorization.history.isEmpty
        guard journal.setEnabled(enabled, owner: uid, data: store.data, page: page, plan: existingPlan ? memorization.plan : nil) else {
            syncStatus = journal.error ?? "تعذر تفعيل المزامنة."; return
        }
        if enabled { scheduleSync() } else { suspendSync(); syncStatus = "المزامنة متوقفة. بيانات الجهاز محفوظة." }
    }
    func authenticationChanged() {
        suspendSync()
        if let owner = NoorReadingSyncJournal.shared.record?.owner, let uid, owner != uid {
            syncStatus = "بيانات الجهاز مرتبطة بحساب آخر؛ لم تُرفع إلى هذا الحساب."; return
        }
        scheduleSync()
    }
    func suspendSync() {
        syncGeneration = UUID(); pendingSync = false; syncTask?.cancel()
        #if NOOR_ACCOUNT_ENABLED
        readingListeners.forEach { $0.remove() }; readingListeners = []; listenerOwner = nil
        #endif
    }
    func enterBackground() { foreground = false; suspendSync() }
    func disconnectLocalSync() {
        suspendSync(); NoorReadingSyncJournal.shared.pause()
        syncStatus = "المزامنة متوقفة. النسخة السحابية تبقى حتى تحذف الحساب."
    }
    private func scheduleSync() {
        #if NOOR_ACCOUNT_ENABLED
        let journal = NoorReadingSyncJournal.shared
        guard foreground, available, let uid, journal.enabled, journal.record?.owner == uid, !deletionRequested else { return }
        ensureSyncListeners(owner: uid)
        if syncing { pendingSync = true; return }
        syncTask?.cancel()
        let token = syncGeneration
        syncTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, token == syncGeneration else { return }
            await performSync()
        }
        #endif
    }
    func syncNow() async {
        #if NOOR_ACCOUNT_ENABLED
        if syncing { await syncTask?.value; return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in guard let self else { return }; await self.performSync() }
        await syncTask?.value
        #endif
    }
    #if NOOR_ACCOUNT_ENABLED
    private func performSync() async {
        let journal = NoorReadingSyncJournal.shared
        guard foreground, !syncing, !busy, !deletionRequested, journal.enabled,
              let user = Auth.auth().currentUser, user.uid == uid, journal.record?.owner == user.uid,
              let localReading = journal.record?.state, let store = syncStore, store.unreadableDeviceData == nil,
              let memorization = syncMemorization, memorization.unreadableHistory == nil,
              let corpus = QuranResources.corpus else { return }
        syncing = true; pendingSync = false; syncStatus = "جارٍ مزامنة تقدمك…"
        let token = syncGeneration, local = localBackup(memorization)
        defer {
            syncing = false
            if pendingSync { scheduleSync() }
        }
        do {
            try await user.reload()
            guard token == syncGeneration, !Task.isCancelled, Auth.auth().currentUser?.uid == user.uid else { return }
            let database = Firestore.firestore()
            let parent = database.collection("users").document(user.uid).collection("private")
            let readingRef = parent.document("readingState"), memoryRef = parent.document("memorization")
            let output = try await database.runTransaction { transaction, errorPointer in
                do {
                    // Firestore requires every read before any write.
                    let readingDoc = try transaction.getDocument(readingRef)
                    let memoryDoc = try transaction.getDocument(memoryRef)
                    var reading = localReading
                    var memory = try MemorizationCloudMerge.merge(local: local, remote: local, corpus: corpus)
                    if readingDoc.exists {
                        guard readingDoc.data()?["version"] as? Int == 1,
                              let bytes = readingDoc.data()?["data"] as? Data else { throw CocoaError(.fileReadCorruptFile) }
                        let remote = try JSONDecoder().decode(NoorReadingCloudState.self, from: NoorCloudPayload.decode(bytes))
                        reading = try NoorReadingCloudState.merge(reading, remote, corpus: corpus)
                    }
                    if memoryDoc.exists {
                        guard memoryDoc.data()?["version"] as? Int == 1,
                              let bytes = memoryDoc.data()?["data"] as? Data else { throw CocoaError(.fileReadCorruptFile) }
                        let remote = try JSONDecoder().decode(MemorizationCloudBackup.self, from: NoorCloudPayload.decode(bytes))
                        memory = try MemorizationCloudMerge.merge(local: local, remote: remote, corpus: corpus)
                        if reading.plan == nil {
                            let legacyDate = (memoryDoc.data()?["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                            reading.plan = .init(value: remote.plan, stamp: .init(date: legacyDate,
                                device: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
                        }
                    }
                    let selectedPlan = reading.plan?.value ?? memory.plan
                    memory = .init(version: 1, plan: selectedPlan,
                        archive: .init(version: 1, history: memory.archive.history, progress: memory.archive.progress, plan: selectedPlan))
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                    for (reference, data, existing) in [(readingRef, try encoder.encode(reading), readingDoc), (memoryRef, try encoder.encode(memory), memoryDoc)] {
                        guard data.count <= NoorCloudPayload.decodedLimit else { throw CocoaError(.fileWriteOutOfSpace) }
                        let compressed = try (data as NSData).compressed(using: .zlib) as Data
                        guard compressed.count <= NoorCloudPayload.compressedLimit else { throw CocoaError(.fileWriteOutOfSpace) }
                        let previous = (existing.data()?["data"] as? Data).flatMap { try? NoorCloudPayload.decode($0) }
                        if previous != data {
                            transaction.setData(["version": 1, "data": compressed, "updatedAt": FieldValue.serverTimestamp()], forDocument: reference)
                        }
                    }
                    return try encoder.encode(NoorSyncResult(reading: reading, memorization: memory))
                } catch { errorPointer?.pointee = error as NSError; return nil }
            }
            guard token == syncGeneration, !Task.isCancelled, Auth.auth().currentUser?.uid == user.uid,
                  journal.enabled, journal.record?.owner == user.uid, let bytes = output as? Data,
                  let latest = journal.record?.state else { return }
            let result = try JSONDecoder().decode(NoorSyncResult.self, from: bytes)
            // Edits made on this device during the network request are merged again.
            let reading = try NoorReadingCloudState.merge(latest, result.reading, corpus: corpus)
            let memory = try MemorizationCloudMerge.merge(local: localBackup(memorization), remote: result.memorization, corpus: corpus)
            applyingSync = true; defer { applyingSync = false }
            if UserDefaults.standard.object(forKey: "noor.sync.preReadingMerge") == nil {
                let snapshot = NoorReadingLocalSnapshot(device: store.data,
                    page: max(1, min(604, UserDefaults.standard.integer(forKey: "noor.mushaf.lastPage"))), plan: memorization.plan)
                UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: "noor.sync.preReadingMerge")
            }
            guard store.update({ data in
                data.bookmarks = reading.bookmarks.filter { $0.value.value }.map(\.key).sorted()
                if let setting = reading.lowMotion { data.lowMotion = setting.value }
                if let setting = reading.largeQuran { data.largeQuran = setting.value }
            }), journal.adopt(reading, owner: user.uid) else { throw CocoaError(.fileWriteUnknown) }
            if let page = reading.page { UserDefaults.standard.set(page.value, forKey: "noor.mushaf.lastPage") }
            guard memorization.restore(memory) else { throw CocoaError(.fileReadCorruptFile) }
            if let plan = reading.plan?.value {
                if memorization.session == nil && memorization.practice == nil {
                    guard memorization.applySyncedPlan(plan) else { throw CocoaError(.fileWriteUnknown) }
                } else { deferredPlan = plan }
            }
            observedMemorization = fingerprint(memorization)
            syncStatus = deferredPlan == nil ? "تقدمك متزامن." : "تقدمك متزامن. تُطبّق الخطة الأحدث بعد إنهاء جلستك."
        } catch {
            if expireIdentityIfNeeded(error) { return }
            guard token == syncGeneration else { return }
            syncStatus = "لم تكتمل المزامنة. تغييرات جهازك محفوظة؛ أعد المحاولة عند توفر الاتصال."
        }
    }
    #endif

    #if NOOR_ACCOUNT_ENABLED
    private var listener: AuthStateDidChangeListenerHandle?
    private var readingListeners: [ListenerRegistration] = []
    private var listenerOwner: String?
    private var remoteBytes: [String: Data] = [:]
    private var seenDocuments = Set<String>()
    private func ensureSyncListeners(owner: String) {
        guard listenerOwner != owner else { return }
        readingListeners.forEach { $0.remove() }; readingListeners = []
        listenerOwner = owner; remoteBytes = [:]; seenDocuments = []
        let parent = Firestore.firestore().collection("users").document(owner).collection("private")
        for name in ["readingState", "memorization"] {
            let registration = parent.document(name).addSnapshotListener { [weak self] document, error in
                Task { @MainActor in
                    guard let self, self.listenerOwner == owner, self.uid == owner, error == nil,
                          let document, !document.metadata.isFromCache, !document.metadata.hasPendingWrites else { return }
                    let bytes = document.data()?["data"] as? Data
                    if !self.seenDocuments.contains(name) || self.remoteBytes[name] != bytes {
                        self.seenDocuments.insert(name); self.remoteBytes[name] = bytes; self.scheduleSync()
                    }
                }
            }
            readingListeners.append(registration)
        }
    }
    init() {
        guard let config = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: config),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["PROJECT_ID"] as? String == "noor-alruh",
              plist["GOOGLE_APP_ID"] as? String == "1:149675464789:ios:32a19ae8e5a62439561cdc",
              plist["BUNDLE_ID"] as? String == Bundle.main.bundleIdentifier,
              let apiKey = plist["API_KEY"] as? String, !apiKey.isEmpty else { return }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        available = true
        connection.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.scheduleSync() }
        }
        connection.start(queue: DispatchQueue(label: "noor.sync.connection"))
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.signedIn = user != nil; self?.uid = user?.uid; self?.name = user?.displayName ?? "حسابك" }
        }
    }
    func refresh() async {
        guard available, let user = Auth.auth().currentUser else { return }
        do { try await user.reload(); signedIn = Auth.auth().currentUser != nil }
        catch {
            if !expireIdentityIfNeeded(error) { message = "تعذّر التحقق من اتصال الحساب. بياناتك المحلية متاحة." }
        }
    }
    private func expireIdentityIfNeeded(_ error: Error) -> Bool {
        let code = (error as NSError).code
        guard [AuthErrorCode.userNotFound.rawValue, AuthErrorCode.userDisabled.rawValue,
               AuthErrorCode.invalidUserToken.rawValue, AuthErrorCode.userTokenExpired.rawValue].contains(code) else { return false }
        suspendSync(); try? Auth.auth().signOut(); signedIn = false; uid = nil
        message = "انتهت جلسة الحساب. بيانات جهازك محفوظة؛ أعد الدخول للمتابعة."
        syncStatus = "توقفت المزامنة حتى إعادة تسجيل الدخول."; return true
    }
    func handle(_ url: URL) {}
    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        guard available, !busy else { return }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { message = "تعذّر بدء تسجيل الدخول بأمان."; nonce = nil; return }
        let value = bytes.map { String(format: "%02x", $0) }.joined(); nonce = value
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        guard available, !busy, let rawNonce = nonce else { return }; nonce = nil; busy = true; defer { busy = false; scheduleSync() }
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
        } catch let error as ASAuthorizationError where error.code == .canceled {
            message = nil
        } catch { message = deletionRequested ? "لم يكتمل حذف الحساب. أعد التحقق من Apple والاتصال وحاول مجددًا." : "لم يكتمل الدخول بحساب Apple. حاول مجددًا." }
    }
    private func deleteUser(_ user: User) async throws {
        let running = syncTask
        disconnectLocalSync()
        await running?.value
        let database = Firestore.firestore(), batch = Firestore.firestore().batch()
        let parent = database.collection("users").document(user.uid).collection("private")
        let deletionRef = database.collection("accountDeletions").document(user.uid)
        let marker = try await deletionRef.getDocument(source: .server)
        if !marker.exists { batch.setData(["deletedAt": FieldValue.serverTimestamp()], forDocument: deletionRef) }
        batch.deleteDocument(parent.document("memorization"))
        batch.deleteDocument(parent.document("readingState"))
        try await batch.commit()
        try await user.delete()
        signedIn = false; uid = nil; deletionRequested = false; name = ""
        message = "حُذف حسابك وبيانات تقدمك السحابية. بيانات جهازك متاحة دون حساب؛ احذفها من الإعدادات إذا أردت."
    }
    func signOut() {
        guard available, !busy else { return }
        suspendSync()
        do { try Auth.auth().signOut(); signedIn = false; uid = nil; deletionRequested = false; name = "" }
        catch { message = "تعذّر تسجيل الخروج." }
    }
    func backup(memorization: MemorizationStore) async {
        if NoorReadingSyncJournal.shared.enabled { await syncNow(); return }
        guard available, !busy, let user = Auth.auth().currentUser, memorization.unreadableHistory == nil else { return }
        guard bindLocalData(owner: user.uid) else { return }
        busy = true; defer { busy = false; scheduleSync() }
        do {
            guard let corpus = QuranResources.corpus else { throw CocoaError(.fileReadCorruptFile) }
            let local = MemorizationCloudBackup(version: 1, plan: memorization.plan,
                archive: .init(version: 1, history: memorization.history, progress: memorization.progress, plan: memorization.plan))
            let database = Firestore.firestore()
            let reference = database.collection("users").document(user.uid).collection("private").document("memorization")
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let document = try transaction.getDocument(reference)
                    var merged = try MemorizationCloudMerge.merge(local: local, remote: local, corpus: corpus)
                    if document.exists {
                        guard document.data()?["version"] as? Int == 1,
                              let bytes = document.data()?["data"] as? Data else { throw CocoaError(.fileReadCorruptFile) }
                        let remote = try JSONDecoder().decode(MemorizationCloudBackup.self, from: NoorCloudPayload.decode(bytes))
                        merged = try MemorizationCloudMerge.merge(local: local, remote: remote, corpus: corpus)
                    }
                    let data = try JSONEncoder().encode(merged)
                    guard data.count <= NoorCloudPayload.decodedLimit else { throw CocoaError(.fileWriteOutOfSpace) }
                    let compressed = try (data as NSData).compressed(using: .zlib) as Data
                    guard compressed.count <= NoorCloudPayload.compressedLimit else { throw CocoaError(.fileWriteOutOfSpace) }
                    transaction.setData(["version": 1, "data": compressed, "updatedAt": FieldValue.serverTimestamp()], forDocument: reference)
                    return true
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            guard Auth.auth().currentUser?.uid == user.uid else { message = "تغيّر الحساب أثناء الحفظ. بقيت بيانات جهازك محفوظة."; return }
            message = "دُمج تقدمك مع نسخة حسابك دون تكرار النتائج. لا تتضمن النسخة صوتك أو تأملاتك."
        } catch { message = "لم تُحفظ النسخة السحابية. تحقق من الاتصال وحاول مجددًا؛ تقدمك المحلي محفوظ." }
    }
    func restore(memorization: MemorizationStore) async {
        if NoorReadingSyncJournal.shared.enabled { await syncNow(); return }
        guard available, !busy, let user = Auth.auth().currentUser else { return }
        guard bindLocalData(owner: user.uid) else { return }
        busy = true; defer { busy = false; scheduleSync() }
        do {
            let document = try await Firestore.firestore().collection("users").document(user.uid).collection("private").document("memorization").getDocument(source: .server)
            guard document.data()?["version"] as? Int == 1,
                  let compressed = document.data()?["data"] as? Data else { throw CocoaError(.fileReadCorruptFile) }
            let data = try NoorCloudPayload.decode(compressed)
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
    @ObservedObject private var syncJournal = NoorReadingSyncJournal.shared
    @State private var syncConsent = false
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
                    Section("مزامنة تقدمك") {
                        Toggle("المزامنة التلقائية", isOn: Binding(get: { syncJournal.enabled && syncJournal.record?.owner == account.uid },
                            set: { if $0 { syncConsent = true } else { account.setSyncEnabled(false) } }))
                            .disabled(account.busy || account.syncing)
                            .accessibilityIdentifier("account.sync")
                        Text(account.syncStatus).font(.subheadline)
                        if let error = syncJournal.error { Text(error).foregroundStyle(.secondary) }
                        if syncJournal.enabled && syncJournal.record?.owner == account.uid {
                            Button("مزامنة الآن") { Task { await account.syncNow() } }.disabled(account.busy || account.syncing)
                        }
                        Text("آخر صفحة، العلامات، خطة الحفظ والتقدم وإعدادات القراءة. لا تُرفع التسجيلات أو التأملات أو موقعك. تُحفظ التغييرات دون اتصال وتُزامن عند فتح التطبيق والاتصال.").font(.caption)
                    }
                    Section(account.name) {
                        Button("حفظ نسخة سحابية من تقدمي") { uploading = true }.disabled(account.busy || account.syncing)
                        Button("استعادة نسخة الحفظ") { restoring = true }.disabled(account.busy || account.syncing)
                        Button("حذف حسابي", role: .destructive) { deleting = true }.disabled(account.busy)
                        if account.deletionRequested {
                            Text("أعد تسجيل الدخول بالطريقة المرتبطة بحسابك لتأكيد الحذف.")
                            SignInWithAppleButton(.continue, onRequest: account.prepareApple) { result in Task { await account.completeApple(result) } }.frame(height: 50).disabled(account.busy)
                            Button("إلغاء الحذف") { account.deletionRequested = false }
                        }
                        Button("تسجيل الخروج") { account.signOut() }.disabled(account.busy)
                        Text("الحفظ السحابي اختياري؛ لا نرفع التسجيلات الصوتية أو التأملات. بيانات الجهاز تبقى بعد تسجيل الخروج.").font(.caption)
                    }
                } else {
                    Section("تسجيل الدخول") {
                        SignInWithAppleButton(.signIn, onRequest: account.prepareApple) { result in Task { await account.completeApple(result) } }
                            .signInWithAppleButtonStyle(.black).frame(height: 50).disabled(account.busy)
                    }
                }
            } else { Section { Text("الدخول بحساب Apple قيد التجهيز، ولم يُفعّل على هذه النسخة بعد.") } }
            #else
            Section { Text("الدخول بحساب Apple قيد التجهيز، ولم يُفعّل على هذه النسخة بعد.") }
            #endif
            if let message = account.message { Section { Text(message) } }
            Section { Text("استخدم حساب Apple نفسه لاستعادة نسختك على جهاز آخر.").font(.caption) }
        }.navigationTitle("حسابي")
            #if NOOR_ACCOUNT_ENABLED
            .confirmationDialog("دمج بيانات هذا الجهاز مع حسابك وتفعيل المزامنة؟ يُحفظ آخر موضع والعلامات وخطة الحفظ وتقدمك وإعدادات القراءة، دون صوتك أو تأملاتك.", isPresented: $syncConsent, titleVisibility: .visible) {
                Button("تفعيل المزامنة") { account.setSyncEnabled(true) }
            }
            .confirmationDialog("حذف الحساب وجميع بيانات تقدمك السحابية نهائيًا؟ تبقى بيانات جهازك حتى تحذفها من الإعدادات.", isPresented: $deleting, titleVisibility: .visible) {
                Button("متابعة حذف الحساب", role: .destructive) { account.deletionRequested = true }
            }
            .confirmationDialog("حفظ خطة الحفظ والسجل والإتقان في الحساب المسجّل حاليًا؟ سيُدمج السجل مع نسخته السحابية دون حذف النتائج السابقة.", isPresented: $uploading, titleVisibility: .visible) {
                Button("حفظ النسخة") { Task { await account.backup(memorization: memorization) } }
            }
            .confirmationDialog("دمج سجل الحفظ السحابي مع سجل هذا الجهاز؟ تبقى الخطة والجلسة المحلية.", isPresented: $restoring, titleVisibility: .visible) {
                Button("دمج النسخة") { Task { await account.restore(memorization: memorization) } }
            }
            #endif
    }
}
