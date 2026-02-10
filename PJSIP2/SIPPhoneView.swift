//
//  SIPPhoneView.swift
//  PJSIP2
//
//  Created by Hualiteq International on 2025/9/24.
//

import SwiftUI
import Combine

struct SIPPhoneView: View {
    @StateObject private var pjsipManager = PJSIPManager.shared
    @State private var phoneNumber = ""
    @State private var stateLabel = "Library not started"
    
    // Mode toggle
    @State private var useDirectMode = true  // true = P2P like Android sample
    
    // P2P Direct Mode Config (matches Android sample)
    @State private var localPort: String = "6000"
    @State private var targetAddress: String = "192.168.1.9:6000"
    
    // SIP Registration Mode Config
    @State private var sipServer = "oraclesbc.com"
    @State private var sipProxy = "sip:10.2.122.6:5060;transport=tcp"
    @State private var sipUsername = "16000"
    @State private var sipPassword = "12388674"
    @State private var showPassword = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // State Label
                Text(stateLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                // Mode Picker
                Picker("Mode", selection: $useDirectMode) {
                    Text("P2P Direct").tag(true)
                    Text("SIP Server").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                if useDirectMode {
                    directModeSection
                } else {
                    registrationModeSection
                }
                
                // Call Section - shown when library is ready
                if pjsipManager.isRegistered {
                    callSection
                }
                
                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationTitle("SIP Phone")
        .onAppear { setupObservers() }
    }
    
    // MARK: - P2P Direct Mode (mirrors Android pjsua2 sample)
    
    private var directModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P2P Direct Call")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Same as Android sample: start library on a port, call IP:port directly")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Local Port
            VStack(alignment: .leading, spacing: 4) {
                Text("Local SIP Port")
                    .font(.caption).foregroundColor(.secondary)
                TextField("6000", text: $localPort)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
            }
            
            // Target Address
            VStack(alignment: .leading, spacing: 4) {
                Text("Target Address (IP:Port)")
                    .font(.caption).foregroundColor(.secondary)
                TextField("192.168.1.9:6000", text: $targetAddress)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            
            if !pjsipManager.isRegistered {
                Button(action: startDirectMode) {
                    Text("Start Library")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Library Running (port \(localPort))")
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
                
                Button(action: stopLibrary) {
                    Text("Stop Library")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - SIP Registration Mode
    
    private var registrationModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SIP Registration")
                .font(.title2)
                .fontWeight(.bold)
            
            if !pjsipManager.isRegistered {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SIP Server").font(.caption).foregroundColor(.secondary)
                    TextField("sip.example.com", text: $sipServer)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Proxy (Optional)").font(.caption).foregroundColor(.secondary)
                    TextField("proxy.example.com", text: $sipProxy)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Username").font(.caption).foregroundColor(.secondary)
                    TextField("username", text: $sipUsername)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password").font(.caption).foregroundColor(.secondary)
                    HStack {
                        if showPassword {
                            TextField("password", text: $sipPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                        } else {
                            SecureField("password", text: $sipPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Button(action: registerWithSIP) {
                    Text("Register")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sipServer.isEmpty || sipUsername.isEmpty || sipPassword.isEmpty)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text("Registered").fontWeight(.medium)
                        Text("\(sipUsername)@\(sipServer)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
                
                Button(action: unregister) {
                    Text("Unregister")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - Call Section
    
    private var callSection: some View {
        VStack(spacing: 16) {
            Text("Make Call")
                .font(.title2)
                .fontWeight(.bold)
            
            if useDirectMode {
                // In P2P mode, show the target address as the call destination
                Text("Target: sip:\(targetAddress)")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            TextField(useDirectMode ? "IP:Port (or use target above)" : "Phone Number or SIP URI", text: $phoneNumber)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(useDirectMode ? .default : .phonePad)
            
            // Current Call Info
            if !pjsipManager.currentCall.isEmpty {
                HStack {
                    Circle()
                        .fill(pjsipManager.callState == .connected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Call: \(pjsipManager.currentCall)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 4)
            }
            
            // Call Buttons
            VStack(spacing: 12) {
                // Make Call
                Button(action: makeCall) {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("Call")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(pjsipManager.callState == .calling || pjsipManager.callState == .connected)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                
                // Answer (incoming only)
                if pjsipManager.callState == .incoming {
                    Button(action: { pjsipManager.answerCall() }) {
                        HStack {
                            Image(systemName: "phone.fill")
                            Text("Answer")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                
                // Hangup
                if pjsipManager.callState == .calling ||
                   pjsipManager.callState == .connected ||
                   pjsipManager.callState == .incoming {
                    Button(action: { pjsipManager.hangupCall() }) {
                        HStack {
                            Image(systemName: "phone.down.fill")
                            Text("Hangup")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            
            // Device Controls
            HStack(spacing: 12) {
                Button(action: { pjsipManager.device.microphoneEnable.toggle() }) {
                    Text("Mic: \(pjsipManager.device.microphoneEnable ? "ON" : "OFF")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                
                Button(action: { pjsipManager.device.speakerEnable.toggle() }) {
                    Text("Speaker: \(pjsipManager.device.speakerEnable ? "ON" : "OFF")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        PJSIPManager.shared.printConsoleLog = true
        
        pjsipManager.observer.registration.onMessage = { state in
            DispatchQueue.main.async { self.stateLabel = state.rawValue }
        }
        pjsipManager.observer.registration.onSuccess = {
            DispatchQueue.main.async { self.stateLabel = "Registration Successful" }
        }
        pjsipManager.observer.registration.onFailure = { state, reason in
            DispatchQueue.main.async { self.stateLabel = "\(state.rawValue): \(reason)" }
        }
        pjsipManager.observer.call.onIncomingCall = { caller in
            DispatchQueue.main.async { self.stateLabel = "Incoming: \(caller)" }
        }
        pjsipManager.observer.call.onCallConnected = {
            DispatchQueue.main.async { self.stateLabel = "Call Connected" }
        }
        pjsipManager.observer.call.onCallEnded = {
            DispatchQueue.main.async { self.stateLabel = "Call Ended" }
        }
    }
    
    // MARK: - Actions
    
    private func startDirectMode() {
        let port = UInt16(localPort) ?? 6000
        stateLabel = "Starting library on port \(port)..."
        pjsipManager.startLibrary(port: port, useUDP: true)
    }
    
    private func stopLibrary() {
        pjsipManager.shutdownLibrary()
        stateLabel = "Library stopped"
    }
    
    private func registerWithSIP() {
        pjsipManager.serverConfig.domain = sipServer
        pjsipManager.serverConfig.proxy = sipProxy
        pjsipManager.username = sipUsername
        pjsipManager.password = sipPassword
        pjsipManager.registerAccount {}
    }
    
    private func unregister() {
        pjsipManager.unregister()
        stateLabel = "Unregistered"
    }
    
    private func makeCall() {
        let destination: String
        if useDirectMode {
            // Use phoneNumber if filled, otherwise use targetAddress
            destination = phoneNumber.isEmpty ? targetAddress : phoneNumber
        } else {
            destination = phoneNumber
        }
        
        guard !destination.isEmpty else { return }
        pjsipManager.makeCall(to: destination)
    }
}
