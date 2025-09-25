import Foundation
import AVFoundation

// MARK: - Error Types
enum PJSIPError: Error, LocalizedError {
    case initializationFailed(status: Int32)
    case transportCreationFailed(status: Int32)
    case accountAddFailed(status: Int32)
    case callFailed(status: Int32)
    case answerFailed(status: Int32)
    case hangupFailed(status: Int32)
    case noTransportAvailable
    case noAccountRegistered
    case invalidCallId
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed(let status):
            return "PJSIP initialization failed with status: \(status)"
        case .transportCreationFailed(let status):
            return "Transport creation failed with status: \(status)"
        case .accountAddFailed(let status):
            return "Account registration failed with status: \(status)"
        case .callFailed(let status):
            return "Call failed with status: \(status)"
        case .answerFailed(let status):
            return "Answer call failed with status: \(status)"
        case .hangupFailed(let status):
            return "Hangup call failed with status: \(status)"
        case .noTransportAvailable:
            return "No transport available for operation"
        case .noAccountRegistered:
            return "No account registered for operation"
        case .invalidCallId:
            return "Invalid call ID"
        }
    }
}

class PJSIPManager: ObservableObject {
    @Published var isRegistered: Bool = false
    @Published var currentCall: String = ""
    @Published var callState: CallState = .idle
    @Published var errorMessage: String = ""
    
    private var accountId: Int32 = -1
    private var callId: Int32 = -1
    private var transportId: Int32 = -1
    
    enum CallState {
        case idle, calling, incoming, connected, disconnected
    }
    
    static let shared = PJSIPManager()
    
    private init() {
        setupPJSIP()
    }
    
    deinit {
        pjsua_destroy()
    }
    
    private func setupPJSIP() {
        do {
            try initializePJSUA()
            try createUDPTransport()
            try startPJSUA()
            print("PJSUA started successfully")
        } catch {
            handleError(error)
        }
    }
    
    private func initializePJSUA() throws {
        let createStatus = pjsua_create()
        guard createStatus == 0 else {
            throw PJSIPError.initializationFailed(status: createStatus)
        }
        
        var config = pjsua_config()
        pjsua_config_default(&config)
        
        // Set callbacks
        config.cb.on_call_state = onCallStateCallback
        config.cb.on_incoming_call = onIncomingCallCallback
        config.cb.on_reg_state = onRegStateCallback
        
        var logConfig = pjsua_logging_config()
        pjsua_logging_config_default(&logConfig)
        logConfig.console_level = 4
        
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
        transportConfig.port = 0 // Use any available port
        
        let status = pjsua_transport_create(PJSIP_TRANSPORT_UDP, &transportConfig, &transportId)
        guard status == 0 else {
            throw PJSIPError.transportCreationFailed(status: status)
        }
        
        print("UDP transport created successfully with ID: \(transportId)")
    }
    
    private func startPJSUA() throws {
        let status = pjsua_start()
        guard status == 0 else {
            throw PJSIPError.initializationFailed(status: status)
        }
    }
    
    func register(server: String, proxy: String? = nil, username: String, password: String) {
        do {
            try performRegistration(server: server, proxy: proxy, username: username, password: password)
        } catch {
            handleError(error)
        }
    }
    
    private func performRegistration(server: String, proxy: String?, username: String, password: String) throws {
        guard transportId != -1 else {
            throw PJSIPError.noTransportAvailable
        }
        
        var accountConfig = pjsua_acc_config()
        pjsua_acc_config_default(&accountConfig)
        
        let sipUri = "sip:\(username)@\(server)"
        let regUri = "sip:\(server)"
        
        let sipString = createPJString(from: sipUri)
        let regString = createPJString(from: regUri)
        let userString = createPJString(from: username)
        let passString = createPJString(from: password)
        let realmString = createPJString(from: "*")
        let schemeString = createPJString(from: "digest")
        
        accountConfig.id = sipString
        accountConfig.reg_uri = regString
        accountConfig.cred_count = 1
        accountConfig.cred_info.0.realm = realmString
        accountConfig.cred_info.0.scheme = schemeString
        accountConfig.cred_info.0.username = userString
        accountConfig.cred_info.0.data_type = 0 // PJSIP_CRED_DATA_PLAIN_PASSWD
        accountConfig.cred_info.0.data = passString
        
        // Configure proxy if provided
        if let proxy = proxy, !proxy.isEmpty {
            let proxyUri = "sip:\(proxy)"
            let proxyString = createPJString(from: proxyUri)
            accountConfig.proxy_cnt = 1
            accountConfig.proxy.0 = proxyString
        }
        
        let status = pjsua_acc_add(&accountConfig, 1, &accountId)
        guard status == 0 else {
            throw PJSIPError.accountAddFailed(status: status)
            print("\(accountId) failed the registration")
        }
        
        print("Account added successfully with ID: \(accountId)")
        if let proxy = proxy, !proxy.isEmpty {
            print("Using proxy: \(proxy)")
        }
    }
    
    func makeCall(to destination: String) {
        do {
            try performCall(to: destination)
        } catch {
            handleError(error)
        }
    }
    
    private func performCall(to destination: String) throws {
        guard accountId != -1 else {
            throw PJSIPError.noAccountRegistered
        }
        
        let uri = "sip:\(destination)"
        let uriString = createPJString(from: uri)
        var uriVar = uriString
        
        let status = pjsua_call_make_call(accountId, &uriVar, .none, nil, nil, &callId)
        guard status == 0 else {
            throw PJSIPError.callFailed(status: status)
        }
        
        DispatchQueue.main.async {
            self.currentCall = destination
            self.callState = .calling
        }
    }
    
    func answerCall() {
        do {
            try performAnswerCall()
        } catch {
            handleError(error)
        }
    }
    
    private func performAnswerCall() throws {
        guard callId != -1 else {
            throw PJSIPError.invalidCallId
        }
        
        let status = pjsua_call_answer(callId, 200, nil, nil)
        guard status == 0 else {
            throw PJSIPError.answerFailed(status: status)
        }
        
        DispatchQueue.main.async {
            self.callState = .connected
        }
    }
    
    func hangupCall() {
        do {
            try performHangupCall()
        } catch {
            handleError(error)
        }
    }
    
    private func performHangupCall() throws {
        guard callId != -1 else {
            throw PJSIPError.invalidCallId
        }
        
        let status = pjsua_call_hangup(callId, 0, nil, nil)
        guard status == 0 else {
            throw PJSIPError.hangupFailed(status: status)
        }
        
        DispatchQueue.main.async {
            self.callState = .disconnected
            self.currentCall = ""
            self.callId = -1
        }
    }
    
    // MARK: - Helper Methods
    
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
        
        print("PJSIP Error: \(errorMessage)")
        
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
        print("Call state changed for call: \(callId)")
        
        var callInfo = pjsua_call_info()
        guard pjsua_call_get_info(callId, &callInfo) == 0 else {
            print("Failed to get call info")
            return
        }
        
        DispatchQueue.main.async {
            switch callInfo.state {
            case PJSIP_INV_STATE_CALLING:
                self.callState = .calling
            case PJSIP_INV_STATE_CONFIRMED:
                self.callState = .connected
            case PJSIP_INV_STATE_DISCONNECTED:
                self.callState = .disconnected
                self.currentCall = ""
                self.callId = -1
            default:
                print("Unhandled call state: \(callInfo.state)")
            }
        }
    }
    
    func handleIncomingCall(accountId: Int32, callId: Int32) {
        self.callId = callId
        
        DispatchQueue.main.async {
            self.callState = .incoming
            
            var callInfo = pjsua_call_info()
            if pjsua_call_get_info(callId, &callInfo) == 0 {
                if let remoteInfo = callInfo.remote_info.ptr {
                    self.currentCall = String(cString: remoteInfo)
                }
            }
        }
    }
    
    func handleRegistrationState(accountId: Int32) {
        var accInfo = pjsua_acc_info()
        guard pjsua_acc_get_info(accountId, &accInfo) == 0 else {
            print("Failed to get account info")
            return
        }
        
        DispatchQueue.main.async {
            self.isRegistered = accInfo.status.rawValue == 200
            print("Registration status: \(accInfo.status)")
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
