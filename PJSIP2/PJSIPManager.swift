import Foundation
import AVFoundation

// MARK: - Main Manager Class
class PJSIPManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = PJSIPManager()
    
    // MARK: - Published Properties
    @Published var isRegistered: Bool = false
    @Published var currentCall: String = ""
    @Published var callState: CallState = .idle
    @Published var errorMessage: String = ""
    
    // MARK: - Public Properties
    public lazy var serverConfig = SIPServerConfig()
    public lazy var device = SIPDevice()
    public lazy var observer = SIPObserver()
    
    public var printConsoleLog: Bool = false
    public lazy var username: String = ""
    public lazy var password: String = ""
    
    public lazy var userData: Dictionary<String, Any> = [:]
    
    // MARK: - Private Properties
    private var accountId: Int32 = -1
    private var callId: Int32 = -1
    private var transportId: Int32 = -1
    private var isLibraryInitialized: Bool = false
    private var isConnecting: Bool = false
    private var task: Task<(), Error>?
    
    // Dedicated queue for PJSIP operations
    private let pjsipQueue = DispatchQueue(label: "com.pjsip.operations", qos: .userInitiated)
    
    private var state: SIPState = .initial {
        didSet {
            OperationQueue.main.addOperation {
                self.observer.registration.onMessage?(self.state)
            }
        }
    }
    
    enum CallState {
        case idle, calling, ringing, incoming, connected, disconnected
    }
    
    // MARK: - Initialization
    private init() {}
    
    deinit {
        shutdownLibrary()
    }
    
    // MARK: - Audio Session (CRITICAL for real device audio)
    
    /// Configure AVAudioSession for VoIP - must be called before audio flows
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            debugPrint("AVAudioSession configured for VoIP")
        } catch {
            debugPrint("AVAudioSession error: \(error.localizedDescription)")
        }
    }
    
    /// Deactivate audio session when call ends
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            debugPrint("AVAudioSession deactivated")
        } catch {
            debugPrint("AVAudioSession deactivate error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Library Lifecycle (mirrors Android's init → start → destroy)
    
    public func startLibrary(port: UInt16 = 6000, useUDP: Bool = true) {
        pjsipQueue.async {
            self.registerThreadIfNeeded()
            
            guard !self.isLibraryInitialized else {
                self.debugPrint("Library already initialized")
                return
            }
            
            do {
                // Step 1: pjsua_create()
                let createStatus = pjsua_create()
                guard createStatus == 0 else {
                    throw PJSIPError.initializationFailed(status: createStatus)
                }
                self.debugPrint("pjsua_create() OK")
                
                // Step 2: Configure and init
                var config = pjsua_config()
                pjsua_config_default(&config)
                config.cb.on_call_state = onCallStateCallback
                config.cb.on_incoming_call = onIncomingCallCallback
                config.cb.on_call_media_state = onCallMediaStateCallback  // IMPORTANT: audio bridge
                config.cb.on_reg_state = onRegStateCallback
                config.thread_cnt = 1
                
                var logConfig = pjsua_logging_config()
                pjsua_logging_config_default(&logConfig)
                logConfig.console_level = self.printConsoleLog ? 4 : 0
                
                var mediaConfig = pjsua_media_config()
                pjsua_media_config_default(&mediaConfig)
                mediaConfig.clock_rate = 16000
                mediaConfig.snd_clock_rate = 0
                
                let initStatus = pjsua_init(&config, &logConfig, &mediaConfig)
                guard initStatus == 0 else {
                    pjsua_destroy()
                    throw PJSIPError.initializationFailed(status: initStatus)
                }
                self.debugPrint("pjsua_init() OK")
                
                // Step 3: Create transport
                var transportConfig = pjsua_transport_config()
                pjsua_transport_config_default(&transportConfig)
                transportConfig.port = UInt32(port)
                
                let transportType = useUDP ? PJSIP_TRANSPORT_UDP : PJSIP_TRANSPORT_TCP
                let transportStatus = pjsua_transport_create(transportType, &transportConfig, &self.transportId)
                guard transportStatus == 0 else {
                    pjsua_destroy()
                    throw PJSIPError.transportCreationFailed(status: transportStatus)
                }
                self.debugPrint("Transport created (ID: \(self.transportId)), port: \(port), UDP: \(useUDP)")
                
                // Step 4: Add local account (no registration)
                var accConfig = pjsua_acc_config()
                pjsua_acc_config_default(&accConfig)
                accConfig.id = self.createPJString(from: "sip:localhost")
                
                let accStatus = pjsua_acc_add(&accConfig, 1, &self.accountId)
                guard accStatus == 0 else {
                    pjsua_destroy()
                    throw PJSIPError.accountAddFailed(status: accStatus)
                }
                self.debugPrint("Local account added (ID: \(self.accountId))")
                
                // Step 5: Start
                let startStatus = pjsua_start()
                guard startStatus == 0 else {
                    pjsua_destroy()
                    throw PJSIPError.initializationFailed(status: startStatus)
                }
                
                self.isLibraryInitialized = true
                self.debugPrint("PJSUA started successfully - RUNNING")
                
                DispatchQueue.main.async {
                    self.state = .registered
                    self.isRegistered = true
                }
                
            } catch {
                self.debugPrint("Library start failed: \(error)")
                DispatchQueue.main.async {
                    self.state = .registrationFailed
                    self.errorMessage = error.localizedDescription
                    self.observer.registration.onFailure?(.failSystemException, error.localizedDescription)
                }
            }
        }
    }
    
    public func shutdownLibrary() {
        pjsipQueue.async {
            self.registerThreadIfNeeded()
            
            guard self.isLibraryInitialized else { return }
            
            pjsua_call_hangup_all()
            
            if self.accountId != -1 {
                pjsua_acc_del(self.accountId)
                self.accountId = -1
            }
            
            pjsua_destroy()
            self.transportId = -1
            self.isLibraryInitialized = false
            
            self.deactivateAudioSession()
            self.debugPrint("PJSUA destroyed")
            
            DispatchQueue.main.async {
                self.isRegistered = false
                self.callState = .idle
                self.currentCall = ""
                self.state = .initial
            }
        }
    }
    
    // MARK: - SIP Account Registration (for registrar-based calling)
    
    public func registerAccount(_ completion: @escaping () -> Void) {
        if isConnecting {
            fail(.failSystemException, "Registration already in progress", cancelTask: false)
            return
        }
        
        isConnecting = true
        state = .initializing
        
        task = executeTask {
            if !self.isLibraryInitialized {
                try self.initLibrarySync()
            }
            
            self.state = .registering
            try await self.performRegistration(
                server: self.serverConfig.domain,
                proxy: self.serverConfig.proxy.isEmpty ? nil : self.serverConfig.proxy,
                username: self.username,
                password: self.password
            )
            completion()
        }
    }
    
    public func unregister() {
        state = .initial
        if accountId != -1 {
            pjsua_acc_del(accountId)
            accountId = -1
        }
        isConnecting = false
        DispatchQueue.main.async {
            self.isRegistered = false
        }
    }
    
    // MARK: - Outgoing Call
    
    public func makeCall(to destination: String, completion: @escaping () -> Void = {}) {
        guard isLibraryInitialized, accountId != -1 else {
            fail(.failSystemException, "Library not initialized. Call startLibrary() first.")
            return
        }
        
        pjsipQueue.async {
            self.registerThreadIfNeeded()
            
            // Configure audio session for real device
            self.configureAudioSession()
            
            // Set null sound device only on simulator
            #if targetEnvironment(simulator)
            let nullSndStatus = pjsua_set_null_snd_dev()
            self.debugPrint("Set null sound device (simulator): \(nullSndStatus == 0 ? "OK" : "Failed(\(nullSndStatus))")")
            #endif
            
            // Build SIP URI
            let uri: String
            if destination.hasPrefix("sip:") {
                uri = destination
            } else {
                uri = "sip:\(destination)"
            }
            
            var uriStr = self.createPJString(from: uri)
            self.debugPrint("Making call to: \(uri)")
            
            let status = pjsua_call_make_call(
                self.accountId,
                &uriStr,
                nil, nil, nil,
                &self.callId
            )
            
            if status == 0 {
                self.debugPrint("Call initiated (ID: \(self.callId))")
                DispatchQueue.main.async {
                    self.currentCall = destination
                    self.callState = .calling
                    self.state = .makingCall
                    completion()
                }
            } else {
                self.debugPrint("Call failed with status: \(status)")
                DispatchQueue.main.async {
                    self.fail(.failSystemException, "Call failed (status: \(status))")
                }
            }
        }
    }
    
    // MARK: - Incoming Call: Answer / Reject
    
    /// Answer incoming call with 200 OK
    /// 180 Ringing was already sent in handleIncomingCall
    public func answerCall() {
        pjsipQueue.async {
            self.registerThreadIfNeeded()
            guard self.callId != -1 else {
                self.debugPrint("answerCall: no active call")
                return
            }
            
            // Configure audio for real device before answering
            self.configureAudioSession()
            
            #if targetEnvironment(simulator)
            let nullSndStatus = pjsua_set_null_snd_dev()
            self.debugPrint("Set null sound device (simulator): \(nullSndStatus == 0 ? "OK" : "Failed(\(nullSndStatus))")")
            #endif
            
            // Answer with 200 OK - establishes media session
            let status = pjsua_call_answer(self.callId, 200, nil, nil)
            if status == 0 {
                self.debugPrint("Answer call 200 OK: success")
                DispatchQueue.main.async {
                    self.callState = .connected
                    self.state = .callConnected
                }
            } else {
                self.debugPrint("Answer call failed: \(status)")
            }
        }
    }
    
    /// Reject incoming call with 486 Busy Here
    public func rejectCall() {
        pjsipQueue.async {
            self.registerThreadIfNeeded()
            guard self.callId != -1 else { return }
            
            let status = pjsua_call_answer(self.callId, 486, nil, nil)
            self.debugPrint("Reject call: \(status == 0 ? "OK" : "Failed(\(status))")")
            
            DispatchQueue.main.async {
                self.callState = .idle
                self.currentCall = ""
                self.callId = -1
            }
        }
    }
    
    /// Hangup active call
    public func hangupCall() {
        pjsipQueue.async {
            self.registerThreadIfNeeded()
            guard self.callId != -1 else { return }
            
            let status = pjsua_call_hangup(self.callId, 0, nil, nil)
            self.debugPrint("Hangup: \(status == 0 ? "OK" : "Failed(\(status))")")
            
            DispatchQueue.main.async {
                self.callState = .idle
                self.currentCall = ""
                self.callId = -1
            }
        }
    }
    
    public func hangupAllCalls() {
        pjsipQueue.async {
            self.registerThreadIfNeeded()
            pjsua_call_hangup_all()
            DispatchQueue.main.async {
                self.callState = .idle
                self.currentCall = ""
                self.callId = -1
            }
        }
    }
    
    // MARK: - Private: Synchronous library init (for registerAccount flow)
    
    private func initLibrarySync() throws {
        guard !isLibraryInitialized else { return }
        
        let createStatus = pjsua_create()
        guard createStatus == 0 else {
            throw PJSIPError.initializationFailed(status: createStatus)
        }
        
        var config = pjsua_config()
        pjsua_config_default(&config)
        config.cb.on_call_state = onCallStateCallback
        config.cb.on_incoming_call = onIncomingCallCallback
        config.cb.on_call_media_state = onCallMediaStateCallback
        config.cb.on_reg_state = onRegStateCallback
        
        var logConfig = pjsua_logging_config()
        pjsua_logging_config_default(&logConfig)
        logConfig.console_level = printConsoleLog ? 4 : 0
        
        var mediaConfig = pjsua_media_config()
        pjsua_media_config_default(&mediaConfig)
        
        let initStatus = pjsua_init(&config, &logConfig, &mediaConfig)
        guard initStatus == 0 else {
            pjsua_destroy()
            throw PJSIPError.initializationFailed(status: initStatus)
        }
        
        var transportConfig = pjsua_transport_config()
        pjsua_transport_config_default(&transportConfig)
        transportConfig.port = 0
        
        let tStatus = pjsua_transport_create(PJSIP_TRANSPORT_TCP, &transportConfig, &transportId)
        guard tStatus == 0 else {
            pjsua_destroy()
            throw PJSIPError.transportCreationFailed(status: tStatus)
        }
        
        let startStatus = pjsua_start()
        guard startStatus == 0 else {
            pjsua_destroy()
            throw PJSIPError.initializationFailed(status: startStatus)
        }
        
        isLibraryInitialized = true
        debugPrint("Library initialized (registrar mode)")
    }
    
    // MARK: - Private: Registration
    
    private func performRegistration(server: String, proxy: String?, username: String, password: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pjsipQueue.async {
                self.registerThreadIfNeeded()
                
                if self.accountId != -1 {
                    pjsua_acc_del(self.accountId)
                    self.accountId = -1
                }
                
                var accountConfig = pjsua_acc_config()
                pjsua_acc_config_default(&accountConfig)
                
                let sipUri = "sip:\(username)@\(server)"
                let regUri = "sip:\(server)"
                
                accountConfig.id = self.createPJString(from: sipUri)
                accountConfig.reg_uri = self.createPJString(from: regUri)
                accountConfig.cred_count = 1
                accountConfig.cred_info.0.realm = self.createPJString(from: "*")
                accountConfig.cred_info.0.scheme = self.createPJString(from: "digest")
                accountConfig.cred_info.0.username = self.createPJString(from: username)
                accountConfig.cred_info.0.data_type = 0
                accountConfig.cred_info.0.data = self.createPJString(from: password)
                
                if let proxy = proxy, !proxy.isEmpty {
                    let proxyUri = proxy.hasPrefix("sip:") ? proxy : "sip:\(proxy)"
                    accountConfig.proxy_cnt = 1
                    accountConfig.proxy.0 = self.createPJString(from: proxyUri)
                }
                
                let status = pjsua_acc_add(&accountConfig, 1, &self.accountId)
                if status == 0 {
                    self.debugPrint("Account registered (ID: \(self.accountId))")
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PJSIPError.accountAddFailed(status: status))
                }
            }
        }
    }
    
    // MARK: - Thread Management
    
    private static let threadLocalKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()
    
    private func registerThreadIfNeeded() {
        if pthread_getspecific(PJSIPManager.threadLocalKey) != nil {
            return
        }
        
        var pjThread: OpaquePointer? = nil
        let threadDescSize = 256
        let threadDesc = UnsafeMutablePointer<Int>.allocate(capacity: threadDescSize / MemoryLayout<Int>.size)
        
        let status = "pjsip_queue".withCString { namePtr in
            pj_thread_register(namePtr, threadDesc, &pjThread)
        }
        
        if status == 0 {
            pthread_setspecific(PJSIPManager.threadLocalKey, UnsafeMutableRawPointer(bitPattern: 1))
            debugPrint("Thread registered for PJSIP")
        }
    }
    
    // MARK: - Helpers
    
    private func executeTask(_ execute: @escaping () async throws -> Void) -> Task<(), Error> {
        return Task {
            do {
                try await execute()
            } catch let error as PJSIPError {
                self.fail(.failSystemException, error.localizedDescription)
            } catch {
                self.fail(.failSystemException, "PJSIP unknown error: \(error.localizedDescription)")
            }
        }
    }
    
    private func fail(_ state: SIPState, _ reason: String, cancelTask: Bool = true) {
        if cancelTask { self.task?.cancel() }
        isConnecting = false
        OperationQueue.main.addOperation {
            self.observer.registration.onFailure?(state, reason)
        }
    }
    
    internal func debugPrint(_ str: String) {
        if printConsoleLog {
            print("[PJSIP] \(str)")
        }
    }
    
    private func createPJString(from swiftString: String) -> pj_str_t {
        let cString = strdup(swiftString)!
        let length = Int32(swiftString.utf8.count)
        return pj_str_t(ptr: cString, slen: pj_ssize_t(length))
    }
    
    func clearError() {
        DispatchQueue.main.async { self.errorMessage = "" }
    }
    
    // MARK: - Callback Handlers
    
    func handleCallStateChange(callId: Int32) {
        var callInfo = pjsua_call_info()
        guard pjsua_call_get_info(callId, &callInfo) == 0 else {
            debugPrint("Failed to get call info for call \(callId)")
            return
        }
        
        let stateValue = callInfo.state
        debugPrint("Call \(callId) state: \(stateValue.rawValue)")
        
        DispatchQueue.main.async {
            switch stateValue {
            case PJSIP_INV_STATE_CALLING:
                self.callState = .calling
                self.state = .callInProgress
                self.debugPrint("Call state: CALLING")
                
            case PJSIP_INV_STATE_INCOMING:
                self.debugPrint("Call state: INCOMING")
                
            case PJSIP_INV_STATE_EARLY:
                self.callState = .ringing
                self.debugPrint("Call state: EARLY (ringing)")
                
            case PJSIP_INV_STATE_CONNECTING:
                self.debugPrint("Call state: CONNECTING")
                
            case PJSIP_INV_STATE_CONFIRMED:
                self.callState = .connected
                self.state = .callConnected
                self.observer.call.onCallConnected?()
                self.debugPrint("Call state: CONFIRMED (connected)")
                
            case PJSIP_INV_STATE_DISCONNECTED:
                let prevState = self.callState
                self.callState = .idle
                self.state = .callEnded
                self.currentCall = ""
                self.callId = -1
                self.observer.call.onCallEnded?()
                self.deactivateAudioSession()
                self.debugPrint("Call state: DISCONNECTED (was: \(prevState))")
                
            default:
                self.debugPrint("Call state: \(stateValue.rawValue)")
            }
        }
    }
    
    /// Handle incoming call - sends 180 Ringing automatically, waits for user to answer/reject
    func handleIncomingCall(accountId: Int32, callId: Int32) {
        self.callId = callId
        
        // Send 180 Ringing immediately so caller hears ringback tone
        pjsipQueue.async {
            self.registerThreadIfNeeded()
            let ringStatus = pjsua_call_answer(callId, 180, nil, nil)
            self.debugPrint("Sent 180 Ringing for call \(callId): \(ringStatus == 0 ? "OK" : "Failed(\(ringStatus))")")
        }
        
        DispatchQueue.main.async {
            self.callState = .incoming
            self.state = .incomingCall
            
            var callInfo = pjsua_call_info()
            if pjsua_call_get_info(callId, &callInfo) == 0 {
                if let remotePtr = callInfo.remote_info.ptr {
                    let remote = String(cString: remotePtr)
                    self.currentCall = remote
                    self.observer.call.onIncomingCall?(remote)
                    self.debugPrint("Incoming call from: \(remote)")
                }
            }
        }
    }
    
    /// Handle media state - connects audio bridge when call media becomes active
    /// WITHOUT THIS, you get a connected call but NO AUDIO
    func handleCallMediaState(callId: Int32) {
        var callInfo = pjsua_call_info()
        guard pjsua_call_get_info(callId, &callInfo) == 0 else {
            debugPrint("handleCallMediaState: failed to get call info")
            return
        }
        
        debugPrint("Media state changed for call \(callId), status: \(callInfo.media_status.rawValue)")
        
        if callInfo.media_status == PJSUA_CALL_MEDIA_ACTIVE {
            let confPort = callInfo.conf_slot
            
            // Connect call's audio to sound device (you hear them)
            pjsua_conf_connect(confPort, 0)
            // Connect sound device to call's audio (they hear you)
            pjsua_conf_connect(0, confPort)
            
            debugPrint("Audio bridge connected: call port \(confPort) <-> sound device 0")
        } else {
            debugPrint("Media not active yet, status: \(callInfo.media_status.rawValue)")
        }
    }
    
    func handleRegistrationState(accountId: Int32) {
        var accInfo = pjsua_acc_info()
        guard pjsua_acc_get_info(accountId, &accInfo) == 0 else { return }
        
        let statusCode = accInfo.status.rawValue
        debugPrint("Registration status: \(statusCode)")
        
        DispatchQueue.main.async {
            let wasRegistered = self.isRegistered
            self.isRegistered = (statusCode == 200)
            self.isConnecting = false
            
            if self.isRegistered && !wasRegistered {
                self.state = .registered
                self.observer.registration.onSuccess?()
            } else if !self.isRegistered && wasRegistered {
                self.state = .registrationFailed
                self.observer.registration.onFailure?(.registrationFailed, "Registration lost (status: \(statusCode))")
            }
        }
    }
}

// MARK: - C Callback Functions

private func onCallStateCallback(call_id: pjsua_call_id, e: UnsafeMutablePointer<pjsip_event>?) {
    PJSIPManager.shared.handleCallStateChange(callId: call_id)
}

private func onIncomingCallCallback(acc_id: pjsua_acc_id, call_id: pjsua_call_id, rdata: UnsafeMutablePointer<pjsip_rx_data>?) {
    PJSIPManager.shared.handleIncomingCall(accountId: acc_id, callId: call_id)
}

private func onCallMediaStateCallback(call_id: pjsua_call_id) {
    PJSIPManager.shared.handleCallMediaState(callId: call_id)
}

private func onRegStateCallback(acc_id: pjsua_acc_id) {
    PJSIPManager.shared.handleRegistrationState(accountId: acc_id)
}
