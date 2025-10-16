//
//  Model.swift
//  PJSIP2
//
//  Created by Hualiteq International on 2025/10/16.
//

import Foundation

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

// MARK: - SIP State (similar to VCSState)
public enum SIPState: String {
    case initial = "Initial"
    case initializing = "Initializing PJSIP"
    case registering = "Registering with SIP server"
    case registered = "Registered successfully"
    case registrationFailed = "Registration failed"
    case makingCall = "Making call"
    case callInProgress = "Call in progress"
    case callConnected = "Call connected"
    case callEnded = "Call ended"
    case incomingCall = "Incoming call"
    case failPermissionNotAllowed = "Permission not allowed"
    case failSystemException = "System exception occurred"
}

// MARK: - Observer Pattern (like VCSObserver)
public class SIPObserver {
    
    public class RegistrationObserver {
        public var onMessage: ((SIPState) -> Void)?
        public var onSuccess: (() -> Void)?
        public var onFailure: ((SIPState, String) -> Void)?
    }
    
    public class CallObserver {
        public var onMessage: ((SIPState) -> Void)?
        public var onSuccess: (() -> Void)?
        public var onFailure: ((String) -> Void)?
        public var onIncomingCall: ((String) -> Void)?
        public var onCallConnected: (() -> Void)?
        public var onCallEnded: (() -> Void)?
    }
    
    public lazy var registration = RegistrationObserver()
    public lazy var call = CallObserver()
}

// MARK: - Server Config (like VCSServerConfig)
public class SIPServerConfig {
    public var domain: String = ""
    public var proxy: String = ""
    public var port: Int = 5060
    public var transport: String = "UDP"
}

// MARK: - Device Settings (like VCSDevice)
public class SIPDevice {
    public var microphoneEnable: Bool = true
    public var speakerEnable: Bool = true
    public var volume: Float = 1.0
}
