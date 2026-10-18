import Foundation
import CryptoKit
#if NOOR_ACCOUNT_ENABLED
import FirebaseCore
import FirebaseAuth
#endif

enum QuranRemoteConsent {
    static let enabledKey = "noor.recitation.remoteConsent.v1"
    private static let ownerKey = "noor.recitation.remoteConsentOwner.v1"
    static var owner: String? {
        #if NOOR_ACCOUNT_ENABLED
        guard FirebaseApp.app() != nil else { return nil }
        return Auth.auth().currentUser?.uid
        #else
        return nil
        #endif
    }
    private static func digest(_ owner: String) -> String {
        SHA256.hash(data:Data(owner.utf8)).map { String(format:"%02x",$0) }.joined()
    }
    static func permits(owner: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let owner else { return false }
        return defaults.bool(forKey:enabledKey) && defaults.string(forKey:ownerKey) == digest(owner)
    }
    static var enabled: Bool { permits(owner:owner) }
    static func configure(_ enabled: Bool, owner: String?, defaults: UserDefaults = .standard) {
        guard enabled, let owner else {
            defaults.set(false,forKey:enabledKey); defaults.removeObject(forKey:ownerKey); return
        }
        defaults.set(digest(owner),forKey:ownerKey)
        defaults.set(true,forKey:enabledKey)
    }
}

/// Public endpoint only. Missing configuration keeps the shipped local engine.
/// No inferred hostname, embedded credential or automatic audio upload.
struct QuranRemoteRecognitionConfiguration: Sendable {
    let endpoint: URL
    init?(url: URL) {
        guard url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        endpoint = url
    }
    static var bundled: Self? {
        #if NOOR_ACCOUNT_ENABLED
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NoorRecitationServerURL") as? String,
              Bundle.main.object(forInfoDictionaryKey: "NoorRemoteProcessingPolicyVersion") as? Int == 1,
              let url = URL(string: value) else { return nil }
        return Self(url: url)
        #else
        return nil
        #endif
    }
}

enum QuranRemoteRecognitionFailure: Error {
    case consentRequired, identityRequired, invalidResponse, serverUnavailable, concurrentWindow, cancelled
}

/// Preserve the source decoder's uncertainty boundaries before native anchoring.
/// Rejected observations are retained locally but can never reveal a Quran word.
enum QuranRemoteWordEvidence {
    struct Word: Decodable {
        let text: String; let start: Double; let end: Double; let confidence: Double; let run_index: Int
    }
    struct Observation: Decodable {
        let occurrence_index: Int; let run_index: Int; let text: String
        let start: Double?; let end: Double?; let confidence: Double?; let recognition_state: String
    }
    static func resolve(words: [Word], observations: [Observation], window: QuranAudioWindow,
                        baseFrame: Int64, unresolved: Bool) throws -> QuranRecognitionWorker.Result {
        guard words.count <= 160, observations.count <= 320, baseFrame >= 0, window.startFrame >= baseFrame,
              window.endFrame > window.startFrame, window.samples.count == Int(window.endFrame-window.startFrame)
            else { throw QuranRemoteRecognitionFailure.invalidResponse }
        let accepted = observations.filter { $0.recognition_state == "accepted" }
        guard accepted.count == words.count, zip(accepted, words).allSatisfy({ source, word in
            source.text == word.text && source.start == word.start && source.end == word.end
                && source.confidence == word.confidence && source.run_index == word.run_index
        }) else { throw QuranRemoteRecognitionFailure.invalidResponse }
        let samples = try QuranRecognitionAudio.conditioned(window.samples)
        // Subtract in the server stream clock first. Adding the take origin
        // before subtracting the window origin can make an exact zero negative.
        let streamStart = Double(window.startFrame-baseFrame) / 16000
        let streamEnd = streamStart + Double(samples.count) / 16000
        var runs: [[QuranHeardWord]] = [[]]
        var saved: [QuranObservedWord] = []
        var uncertain = unresolved
        var previousRun = 0
        var previousEnd: Double = 0
        for (index, source) in observations.enumerated() {
            guard source.occurrence_index == index, (previousRun...320).contains(source.run_index),
                  !source.text.isEmpty, source.text.count <= 128,
                  ["accepted", "unassessable"].contains(source.recognition_state),
                  source.confidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                  (source.start == nil) == (source.end == nil) else { throw QuranRemoteRecognitionFailure.invalidResponse }
            if source.run_index != previousRun { runs.append([]) }
            previousRun = source.run_index
            if let start = source.start, let end = source.end {
                guard start.isFinite, end.isFinite, start >= streamStart, end > start,
                      end <= streamEnd else { throw QuranRemoteRecognitionFailure.invalidResponse }
            }
            let start = source.start.map { $0-streamStart }, end = source.end.map { $0-streamStart }
            let takeStart = start.map { window.offset+$0 }, takeEnd = end.map { window.offset+$0 }
            var usable = false
            if source.recognition_state == "accepted", let start, let end, let confidence = source.confidence {
                usable = start >= previousEnd && QuranAlignedWord.tokens([source.text]).count == 1
                    && AudioEvidenceGate.rejection(.init(start: Float(start), end: Float(end), probability: Float(confidence)), samples: samples) == nil
                if usable { runs[runs.count-1].append(.init(text: source.text, start: start, end: end, probability: confidence)) }
            }
            if let end { previousEnd = max(previousEnd, end) }
            saved.append(.init(occurrenceIndex: index, runIndex: runs.count-1, observedText: source.text,
                startInTakeSeconds: takeStart, endInTakeSeconds: takeEnd, backendConfidence: source.confidence,
                recognitionState: usable ? "accepted" : "unassessable", timingSource: start == nil ? "unavailable" : "backend-word"))
            if !usable { uncertain = true; runs.append([]) }
        }
        return .init(runs: runs.filter { !$0.isEmpty }, hasUnresolvedSpeech: uncertain, observations: saved)
    }
}

/// Remote recognition still returns source words to the existing local acoustic
/// gate / native-ID tracker / durable journal. Server event IDs cannot directly
/// reveal scripture, award progress or assert pronunciation correctness.
actor QuranRemoteRecognitionProvider: QuranSpeechRecognitionProvider {
    nonisolated var capabilities: QuranRecognitionCapabilities {
        .init(backendID: "noor-self-hosted-1", modelID: "OdyAsh/faster-whisper-base-ar-quran",
              modelRevision: "8578bafd427d122f671b187706650e76edf6f86f", configuredLanguage: "ar",
              delivery: .overlappingAudioWindows, processesLocally: false, wordTimestamps: true,
              wordConfidence: true, phonemeEvidence: false, calibratedWordingAssessment: false,
              validatedTajweedAssessment: false)
    }
    private let configuration: QuranRemoteRecognitionConfiguration
    private let identity: @Sendable () async throws -> String
    private let identityOwner: @Sendable () async -> String?
    private let session: URLSession
    private let ownsSession: Bool
    private var access: String?
    private var activeOwner: String?
    private var refreshToken: String?
    private var accessExpiry = Date.distantPast
    private var sessionID: String?
    private var socket: URLSessionWebSocketTask?
    private var sequence = 0
    private var baseFrame: Int64?
    private var failedWindow = false
    private var busy = false
    private var generation = UUID()
    private var eventReducer = QuranRemoteEventReducer()
    private struct Tokens: Decodable { let access_token: String; let refresh_token: String; let expires_in: Int }
    init(configuration: QuranRemoteRecognitionConfiguration,
         identity: @escaping @Sendable () async throws -> String,
         identityOwner: @escaping @Sendable () async -> String?, session: URLSession? = nil) {
        self.configuration = configuration; self.identity = identity; self.identityOwner = identityOwner
        ownsSession = session == nil
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 25; options.timeoutIntervalForResource = 45
        options.httpShouldSetCookies = false; options.urlCache = nil
        self.session = session ?? URLSession(configuration: options, delegate: QuranRemoteRedirectGuard(), delegateQueue: nil)
    }
    private func request(_ path: String, method: String = "GET", body: Data? = nil,
                         authenticated: Bool = true, credential: String? = nil) async throws -> Data {
        var request = URLRequest(url: configuration.endpoint.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let bearer = credential ?? access { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw QuranRemoteRecognitionFailure.serverUnavailable
        }
        var bytes = Data()
        for try await byte in stream {
            guard bytes.count < 1_000_000 else { throw QuranRemoteRecognitionFailure.invalidResponse }
            bytes.append(byte)
        }
        return bytes
    }
    func prepare() async throws {
        guard QuranRemoteConsent.enabled else {
            throw QuranRemoteRecognitionFailure.consentRequired
        }
        guard let owner = await identityOwner() else { throw QuranRemoteRecognitionFailure.identityRequired }
        if sessionID != nil {
            guard activeOwner == owner else { throw QuranRemoteRecognitionFailure.identityRequired }
            return
        }
        let token = generation
        if access == nil || activeOwner != owner || Date().addingTimeInterval(30) >= accessExpiry {
            let id = try await identity()
            struct Login: Encodable { let identity_token: String }
            let bytes = try await request("v1/auth/firebase", method: "POST",
                body: JSONEncoder().encode(Login(identity_token: id)), authenticated: false)
            let credential = try JSONDecoder().decode(Tokens.self, from: bytes)
            guard !Task.isCancelled, generation == token, await identityOwner() == owner else { throw CancellationError() }
            access = credential.access_token; activeOwner = owner
            refreshToken = credential.refresh_token; accessExpiry = Date().addingTimeInterval(Double(credential.expires_in))
        }
        let ready = try await request("health/ready")
        struct Ready: Decodable { let model_id: String; let model_revision: String; let corpus_version: String; let word_evidence_version: Int }
        let model = try JSONDecoder().decode(Ready.self, from: ready)
        guard model.word_evidence_version == 2, model.model_id == capabilities.modelID, model.model_revision == capabilities.modelRevision,
              model.corpus_version == "1968cf3a4e8338ae2056b5fba309099d2f7645b1609062cc1a52eac1804c5951" else {
            throw QuranRemoteRecognitionFailure.invalidResponse
        }
        struct Start: Encodable { let consent = "transient-audio-encrypted-recovery-1h" }
        struct Created: Decodable { let session_id: String }
        let created = try await request("v1/sessions", method: "POST", body: JSONEncoder().encode(Start()))
        let sid = try JSONDecoder().decode(Created.self, from: created).session_id
        guard !Task.isCancelled, generation == token else { throw CancellationError() }
        sessionID = sid; sequence = 0; baseFrame = nil; failedWindow = false
        eventReducer = QuranRemoteEventReducer(); connect()
    }
    private func connect() {
        guard let sessionID, let access else { return }
        var parts = URLComponents(url: configuration.endpoint.appendingPathComponent("v1/sessions/\(sessionID)/audio"), resolvingAgainstBaseURL: false)!
        parts.scheme = "wss"
        var request = URLRequest(url: parts.url!)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 1_000_000
        task.resume(); socket = task
    }
    private struct Header: Encodable {
        let sequence: Int; let start_frame: Int64; let end_frame: Int64
    }
    private struct Response: Decodable {
        let sequence: Int
        let words: [QuranRemoteWordEvidence.Word]
        let observations: [QuranRemoteWordEvidence.Observation]
        let has_unresolved_speech: Bool
        let events: [QuranRemoteEventReducer.Event]
        let processing_configuration: String
    }
    func recognize(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result {
        guard !failedWindow else { throw URLError(.timedOut) }
        do { return try await recognizeWindow(window) }
        catch is CancellationError { throw CancellationError() }
        catch {
            // An unacknowledged sequence may already be committed remotely.
            // Never reuse it for a DIFFERENT next window or skip the gap. The
            // controller stops its tracking pump but preserves local capture.
            failedWindow = true
            throw URLError(.timedOut)
        }
    }
    private func recognizeWindow(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result {
        guard !busy else { throw QuranRemoteRecognitionFailure.concurrentWindow }
        guard QuranRemoteConsent.enabled else {
            await endTake(); throw QuranRemoteRecognitionFailure.consentRequired
        }
        busy = true; defer { busy = false }
        let token = generation
        try await prepare()
        guard activeOwner == (await identityOwner()) else { throw QuranRemoteRecognitionFailure.identityRequired }
        if Date().addingTimeInterval(30) >= accessExpiry {
            guard let refreshToken else { throw QuranRemoteRecognitionFailure.identityRequired }
            struct Refresh: Encodable { let refresh_token: String }
            let bytes = try await request("v1/auth/refresh", method: "POST",
                body: JSONEncoder().encode(Refresh(refresh_token: refreshToken)), authenticated: false)
            let credential = try JSONDecoder().decode(Tokens.self, from: bytes)
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            access = credential.access_token; self.refreshToken = credential.refresh_token
            accessExpiry = Date().addingTimeInterval(Double(credential.expires_in))
            socket?.cancel(with: .goingAway, reason: nil); connect()
        }
        let sequence = self.sequence
        let base = baseFrame ?? window.startFrame; baseFrame = base
        let streamStart = window.startFrame-base, streamEnd = window.endFrame-base
        guard streamStart >= 0 else { throw QuranRemoteRecognitionFailure.invalidResponse }
        let header = try JSONEncoder().encode(Header(sequence: sequence, start_frame: streamStart, end_frame: streamEnd))
        guard window.samples.count <= 128_000, window.samples.count == Int(window.endFrame-window.startFrame),
              window.samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else { throw QuranCaptureFailure.invalidSamples }
        var bytes = Data(capacity: window.samples.count * 4)
        for sample in window.samples { var value = sample.bitPattern.littleEndian; withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) } }
        var response: Response?
        // Retry exactly the same sequence and bytes once after a disconnect.
        // The server replays the committed result rather than reprocessing PCM.
        for attempt in 0..<2 {
            do {
                guard let socket else { throw QuranRemoteRecognitionFailure.serverUnavailable }
                let message = try await withTaskCancellationHandler(operation: {
                    try await socket.send(.string(String(decoding: header, as: UTF8.self)))
                    try await socket.send(.data(bytes))
                    return try await socket.receive()
                }, onCancel: { socket.cancel(with: .goingAway, reason: nil) })
                let data: Data
                switch message { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: throw QuranRemoteRecognitionFailure.invalidResponse }
                response = try JSONDecoder().decode(Response.self, from: data)
                break
            } catch {
                if attempt == 1 || Task.isCancelled { throw error }
                socket?.cancel(with: .goingAway, reason: nil); connect()
            }
        }
        guard !Task.isCancelled, generation == token, activeOwner == (await identityOwner()),
              let response, response.sequence == sequence,
              response.words.count <= 160 else { throw QuranRemoteRecognitionFailure.invalidResponse }
        guard let sessionID else { throw QuranRemoteRecognitionFailure.invalidResponse }
        try eventReducer.consume(response.events, session: sessionID, sequence: sequence,
            startFrame: streamStart, endFrame: streamEnd)
        var result = try QuranRemoteWordEvidence.resolve(words: response.words, observations: response.observations,
            window: window, baseFrame: base, unresolved: response.has_unresolved_speech)
        self.sequence += 1
        result.windowID = UUID(); result.processingConfiguration = response.processing_configuration
        return result
    }
    func endTake() async {
        generation = UUID(); socket?.cancel(with: .goingAway, reason: nil); socket = nil
        let previous = sessionID, credential = access; sessionID = nil; sequence = 0; access = nil
        baseFrame = nil; failedWindow = false
        refreshToken = nil; accessExpiry = .distantPast
        activeOwner = nil
        guard let credential else { return }
        if let previous { _ = try? await request("v1/sessions/\(previous)", method: "DELETE", credential: credential) }
        _ = try? await request("v1/auth/logout", method: "POST", credential: credential)
    }
    deinit {
        socket?.cancel(with: .goingAway, reason: nil)
        if ownsSession { session.invalidateAndCancel() }
    }
}

/// Immutable delegate: a configured host may not redirect identity tokens or
/// audio to another destination, even if its TLS endpoint returns307/308.
final class QuranRemoteRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum QuranRemoteAccountDeletion {
    @MainActor static func deleteIfConfigured() async throws {
        guard let configuration = QuranRemoteRecognitionConfiguration.bundled else { return }
        #if NOOR_ACCOUNT_ENABLED
        guard let user = Auth.auth().currentUser else { throw QuranRemoteRecognitionFailure.identityRequired }
        let token = try await user.getIDToken()
        guard !Task.isCancelled, Auth.auth().currentUser?.uid == user.uid else { throw CancellationError() }
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 10; options.timeoutIntervalForResource = 20
        options.httpShouldSetCookies = false; options.urlCache = nil
        let network = URLSession(configuration: options, delegate: QuranRemoteRedirectGuard(), delegateQueue: nil)
        defer { network.invalidateAndCancel() }
        var login = URLRequest(url: configuration.endpoint.appendingPathComponent("v1/auth/firebase"))
        login.httpMethod = "POST"; login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.httpBody = try JSONSerialization.data(withJSONObject: ["identity_token":token])
        let (bytes, response) = try await network.data(for: login)
        guard !Task.isCancelled, Auth.auth().currentUser?.uid == user.uid else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let access = object["access_token"] as? String else { throw QuranRemoteRecognitionFailure.serverUnavailable }
        var deletion = URLRequest(url: configuration.endpoint.appendingPathComponent("v1/account"))
        deletion.httpMethod = "DELETE"; deletion.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (_, removed) = try await network.data(for: deletion)
        guard (removed as? HTTPURLResponse)?.statusCode == 200 else { throw QuranRemoteRecognitionFailure.serverUnavailable }
        #endif
    }
}

/// The protocol exposes a synchronous capability snapshot. Its immutable value
/// is protected for reads outside the routing actor; no provider escapes here.
private final class QuranRecognitionCapabilitySnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var value: QuranRecognitionCapabilities
    init(_ value: QuranRecognitionCapabilities) { self.value = value }
    func read() -> QuranRecognitionCapabilities { lock.lock(); defer { lock.unlock() }; return value }
    func write(_ value: QuranRecognitionCapabilities) { lock.lock(); defer { lock.unlock() }; self.value = value }
}

actor QuranRecognitionRouter: QuranSpeechRecognitionProvider {
    private let local: any QuranSpeechRecognitionProvider
    private let remoteAllowed: @Sendable () -> Bool
    private let makeRemote: @Sendable () -> (any QuranSpeechRecognitionProvider)?
    private var current: any QuranSpeechRecognitionProvider
    private var preparedForTake = false
    private var generation = UUID()
    private nonisolated let source: QuranRecognitionCapabilitySnapshot
    nonisolated var capabilities: QuranRecognitionCapabilities { source.read() }
    init(local: any QuranSpeechRecognitionProvider = QuranRecognitionWorker.shared,
         remoteAllowed: @escaping @Sendable () -> Bool = { QuranRemoteConsent.enabled && QuranRemoteRecognitionConfiguration.bundled != nil },
         makeRemote: (@Sendable () -> (any QuranSpeechRecognitionProvider)?)? = nil) {
        self.local = local; self.current = local; self.source = QuranRecognitionCapabilitySnapshot(local.capabilities)
        self.remoteAllowed = remoteAllowed
        self.makeRemote = makeRemote ?? {
            guard let configuration = QuranRemoteRecognitionConfiguration.bundled else { return nil }
            return QuranRemoteRecognitionProvider(configuration: configuration, identity: {
                #if NOOR_ACCOUNT_ENABLED
                guard let user = Auth.auth().currentUser else { throw QuranRemoteRecognitionFailure.identityRequired }
                return try await user.getIDToken()
                #else
                throw QuranRemoteRecognitionFailure.identityRequired
                #endif
            }, identityOwner: {
                #if NOOR_ACCOUNT_ENABLED
                return Auth.auth().currentUser?.uid
                #else
                return nil
                #endif
            })
        }
    }
    func prepare() async throws {
        if !current.capabilities.processesLocally && !remoteAllowed() {
            await endTake(); throw QuranRemoteRecognitionFailure.consentRequired
        }
        if !preparedForTake {
            current = remoteAllowed() ? (makeRemote() ?? local) : local
            source.write(current.capabilities); preparedForTake = true
        }
        let token = generation
        try await current.prepare()
        guard token == generation else { throw CancellationError() }
    }
    func recognize(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result {
        if !current.capabilities.processesLocally && !remoteAllowed() {
            await endTake(); throw QuranRemoteRecognitionFailure.consentRequired
        }
        let token = generation
        let value = try await current.recognize(window)
        guard token == generation else { throw CancellationError() }
        return value
    }
    func endTake() async {
        let previous = current; generation = UUID(); current = local; preparedForTake = false
        source.write(local.capabilities)
        await previous.endTake()
    }
}
