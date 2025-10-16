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
    
    // MARK: - Public Properties (like VCS)
    public lazy var serverConfig = SIPServerConfig()
    public lazy var device = SIPDevice()
    public lazy var observer = SIPObserver()
    
    public var printConsoleLog: Bool = false
    public lazy var username: String = ""
    public lazy var password: String = ""
    
    // User data dictionary (similar to VCS.shared.userData)
    public lazy var userData: Dictionary<String, Any> = [:]
    
    // MARK: - Private Properties
    private var accountId: Int32 = -1
    private var callId: Int32 = -1
    private var transportId: Int32 = -1
    private var isConnecting: Bool = false
    private var task: Task<(), Error>?
    
    // Dedicated queue for PJSIP operations
    private let pjsipQueue = DispatchQueue(label: "com.pjsip.operations", qos: .userInitiated)
    private var isThreadRegistered = false
    
    private var state: SIPState = .initial {
        didSet {
            OperationQueue.main.addOperation {
                self.observer.registration.onMessage?(self.state)
            }
        }
    }
    
    enum CallState {
        case idle, calling, incoming, connected, disconnected
    }
    
    // MARK: - Initialization
    private init() {
        // Don't initialize PJSIP here - wait for explicit registration
    }
    
    deinit {
        pjsua_destroy()
    }
    
    // MARK: - Public Methods (like VCS.shared.requireAgent)
    public func registerAccount(_ completion: @escaping () -> Void) {
        if isConnecting {
            fail(.failSystemException, "Registration already in progress", cancelTask: false)
            return
        }
        
        isConnecting = true
        state = .initializing
        
        task = executeTask {
            // Initialize PJSIP if not already done
            if self.transportId == -1 {
                try self.initializePJSUA()
                try self.createUDPTransport()
                try self.startPJSUA()
                self.debugPrint("PJSUA started successfully")
            }
            
            self.state = .registering
            
            try await self.performRegistration(
                server: self.serverConfig.domain,
                proxy: self.serverConfig.proxy.isEmpty ? nil : self.serverConfig.proxy,
                username: self.username,
                password: self.password
            )
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
    
    public func makeCall(to destination: String, completion: @escaping () -> Void = {}) {
        guard accountId != -1 else {
            fail(.failSystemException, "No account registered")
            return
        }
        
        state = .makingCall
        
        task = executeTask {
            try await self.performCall(to: destination)
        }
    }
    
    public func answerCall() {
        task = executeTask {
            try await self.performAnswerCall()
        }
    }
    
    public func hangupCall() {
        task = executeTask {
            try await self.performHangupCall()
        }
    }
    
    // MARK: - Private Implementation Methods
    private func initializePJSUA() throws {
        let createStatus = pjsua_create()
        guard createStatus == 0 else {
            throw PJSIPError.initializationFailed(status: createStatus)
        }
        
        var config = pjsua_config()
        pjsua_config_default(&config)
        
        config.cb.on_call_state = onCallStateCallback
        config.cb.on_incoming_call = onIncomingCallCallback
        config.cb.on_reg_state = onRegStateCallback
        
        var logConfig = pjsua_logging_config()
        pjsua_logging_config_default(&logConfig)
        logConfig.console_level = printConsoleLog ? 4 : 0
        
        var mediaConfig = pjsua_media_config()
        pjsua_media_config_default(&mediaConfig)
        
        let initStatus = pjsua_init(&config, &logConfig, &mediaConfig)
        guard initStatus == 0 else {
            throw PJSIPError.initializationFailed(status: initStatus)
        }
    }
    
    private func createUDPTransport() throws {
        var transportConfig = pjsua_transport_config()
        pjsua_transport_config_default(&transportConfig)
        transportConfig.port = 0
        
        let status = pjsua_transport_create(PJSIP_TRANSPORT_UDP, &transportConfig, &transportId)
        guard status == 0 else {
            throw PJSIPError.transportCreationFailed(status: status)
        }
        debugPrint("UDP transport created successfully with ID: \(transportId)")
    }
    
    private func startPJSUA() throws {
        let status = pjsua_start()
        guard status == 0 else {
            throw PJSIPError.initializationFailed(status: status)
        }
    }
    
    private func performRegistration(server: String, proxy: String?, username: String, password: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pjsipQueue.async {
                self.registerThreadIfNeeded()
                
                guard self.transportId != -1 else {
                    continuation.resume(throwing: PJSIPError.noTransportAvailable)
                    return
                }
                
                var accountConfig = pjsua_acc_config()
                pjsua_acc_config_default(&accountConfig)
                
                let sipUri = "sip:\(username)@\(server)"
                let regUri = "sip:\(server)"
                
                let sipString = self.createPJString(from: sipUri)
                let regString = self.createPJString(from: regUri)
                let userString = self.createPJString(from: username)
                let passString = self.createPJString(from: password)
                let realmString = self.createPJString(from: "*")
                let schemeString = self.createPJString(from: "digest")
                 
                accountConfig.id = sipString
                accountConfig.reg_uri = regString
                accountConfig.cred_count = 1
                accountConfig.cred_info.0.realm = realmString
                accountConfig.cred_info.0.scheme = schemeString
                accountConfig.cred_info.0.username = userString
                accountConfig.cred_info.0.data_type = 0
                accountConfig.cred_info.0.data = passString
                
                if let proxy = proxy, !proxy.isEmpty {
                    let proxyUri = "sip:\(proxy)"
                    let proxyString = self.createPJString(from: proxyUri)
                    accountConfig.proxy_cnt = 1
                    accountConfig.proxy.0 = proxyString
                }
                
                let status = pjsua_acc_add(&accountConfig, 1, &self.accountId)
                if status == 0 {
                    self.debugPrint("Account added successfully with ID: \(self.accountId)")
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PJSIPError.accountAddFailed(status: status))
                }
            }
        }
    }
    
    private func performCall(to destination: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pjsipQueue.async {
                self.registerThreadIfNeeded()
                
                guard self.accountId != -1 else {
                    continuation.resume(throwing: PJSIPError.noAccountRegistered)
                    return
                }
                
                let uri = destination.hasPrefix("sip:") ? destination : "sip:\(destination)"
                let uriString = self.createPJString(from: uri)
                var uriVar = uriString
                
                let status = pjsua_call_make_call(self.accountId, &uriVar, .none, nil, nil, &self.callId)
                
                if status == 0 {
                    DispatchQueue.main.async {
                        self.currentCall = destination
                        self.callState = .calling
                    }
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PJSIPError.callFailed(status: status))
                }
            }
        }
    }
    
    private func performAnswerCall() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pjsipQueue.async {
                self.registerThreadIfNeeded()
                
                guard self.callId != -1 else {
                    continuation.resume(throwing: PJSIPError.invalidCallId)
                    return
                }
                
                let status = pjsua_call_answer(self.callId, 200, nil, nil)
                
                if status == 0 {
                    DispatchQueue.main.async {
                        self.callState = .connected
                    }
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PJSIPError.answerFailed(status: status))
                }
            }
        }
    }
    
    private func performHangupCall() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pjsipQueue.async {
                self.registerThreadIfNeeded()
                
                guard self.callId != -1 else {
                    continuation.resume(throwing: PJSIPError.invalidCallId)
                    return
                }
                
                let status = pjsua_call_hangup(self.callId, 0, nil, nil)
                
                if status == 0 {
                    DispatchQueue.main.async {
                        self.callState = .disconnected
                        self.currentCall = ""
                        self.callId = -1
                    }
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PJSIPError.hangupFailed(status: status))
                }
            }
        }
    }
    
    // MARK: - Thread Management

    // MARK: - Thread Management

    // MARK: - Thread Management

    private static let threadLocalKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    private func registerThreadIfNeeded() {
        // Check if this specific thread is already registered
        if pthread_getspecific(PJSIPManager.threadLocalKey) != nil {
            return
        }
        
        var pjThread: OpaquePointer? = nil
        let threadDescSize = 256 // Allocate sufficient space
        let threadDesc = UnsafeMutablePointer<Int>.allocate(capacity: threadDescSize / MemoryLayout<Int>.size)
        defer {
            threadDesc.deallocate()
        }
        
        let status = "pjsip_queue".withCString { namePtr in
            pj_thread_register(namePtr, threadDesc, &pjThread)
        }
        
        if status == 0 {
            pthread_setspecific(PJSIPManager.threadLocalKey, UnsafeMutableRawPointer(bitPattern: 1))
            debugPrint("PJSIP queue thread registered successfully")
        } else {
            debugPrint("Failed to register PJSIP thread with status: \(status)")
        }
    }
    
    // MARK: - Helper Methods (like VCS)
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
        if cancelTask {
            self.task?.cancel()
        }
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
        let cString = swiftString.cString(using: .utf8)!
        let length = Int32(swiftString.utf8.count)
        return pj_str_t(ptr: UnsafeMutablePointer(mutating: cString), slen: pj_ssize_t(length))
    }
    
    private func handleError(_ error: Error) {
        let errorMessage: String
        if let pjsipError = error as? PJSIPError {
            errorMessage = pjsipError.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }
        
        debugPrint("Error: \(errorMessage)")
        
        DispatchQueue.main.async {
            self.errorMessage = errorMessage
        }
    }
    
    func clearError() {
        DispatchQueue.main.async {
            self.errorMessage = ""
        }
    }
    
    // MARK: - Callback Handlers
    func handleCallStateChange(callId: Int32) {
        debugPrint("Call state changed for call: \(callId)")
        
        var callInfo = pjsua_call_info()
        guard pjsua_call_get_info(callId, &callInfo) == 0 else {
            debugPrint("Failed to get call info")
            return
        }
        
        DispatchQueue.main.async {
            switch callInfo.state {
            case PJSIP_INV_STATE_CALLING:
                self.callState = .calling
                self.state = .callInProgress
            case PJSIP_INV_STATE_CONFIRMED:
                self.callState = .connected
                self.state = .callConnected
                self.observer.call.onCallConnected?()
            case PJSIP_INV_STATE_DISCONNECTED:
                self.callState = .disconnected
                self.state = .callEnded
                self.currentCall = ""
                self.callId = -1
                self.observer.call.onCallEnded?()
            default:
                self.debugPrint("Unhandled call state: \(callInfo.state)")
            }
        }
    }
    
    func handleIncomingCall(accountId: Int32, callId: Int32) {
        self.callId = callId
        
        DispatchQueue.main.async {
            self.callState = .incoming
            self.state = .incomingCall
            
            var callInfo = pjsua_call_info()
            if pjsua_call_get_info(callId, &callInfo) == 0 {
                if let remoteInfo = callInfo.remote_info.ptr {
                    self.currentCall = String(cString: remoteInfo)
                    self.observer.call.onIncomingCall?(self.currentCall)
                }
            }
        }
    }
    
    func handleRegistrationState(accountId: Int32) {
        var accInfo = pjsua_acc_info()
        guard pjsua_acc_get_info(accountId, &accInfo) == 0 else {
            debugPrint("Failed to get account info")
            return
        }
        
        DispatchQueue.main.async {
            let wasRegistered = self.isRegistered
            self.isRegistered = accInfo.status.rawValue == 200
            self.isConnecting = false
            
            if self.isRegistered && !wasRegistered {
                self.state = .registered
                self.observer.registration.onSuccess?()
            } else if !self.isRegistered && wasRegistered {
                self.state = .registrationFailed
                self.observer.registration.onFailure?(.registrationFailed, "Registration lost")
            }
            
            self.debugPrint("Registration status: \(accInfo.status)")
        }
    }
}

// MARK: - C Callback Functions
@_cdecl("onCallStateCallback")
func onCallStateCallback(call_id: pjsua_call_id, e: UnsafeMutablePointer<pjsip_event>?) -> Void {
    PJSIPManager.shared.handleCallStateChange(callId: call_id)
}

@_cdecl("onIncomingCallCallback")
func onIncomingCallCallback(acc_id: pjsua_acc_id, call_id: pjsua_call_id, rdata: UnsafeMutablePointer<pjsip_rx_data>?) -> Void {
    PJSIPManager.shared.handleIncomingCall(accountId: acc_id, callId: call_id)
}

@_cdecl("onRegStateCallback")
func onRegStateCallback(acc_id: pjsua_acc_id) -> Void {
    PJSIPManager.shared.handleRegistrationState(accountId: acc_id)
}
