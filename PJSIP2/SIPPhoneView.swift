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
    @State private var stateLabel = "N/A"
    
    // SIP Configuration Fields
    @State private var sipServer = "oraclesbc.com"
    @State private var sipProxy = "sip:10.2.122.6:5060;transport=tcp"
    @State private var sipUsername = "16000"
    @State private var sipPassword = "12388674"
    @State private var showPassword = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // State Label (similar to ViewController's stateLabel)
                Text(stateLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                // Registration Section
                if !pjsipManager.isRegistered {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SIP Registration")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        // SIP Server
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SIP Server")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("sip.example.com", text: $sipServer)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        // SIP Proxy (Optional)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Proxy (Optional)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("proxy.example.com", text: $sipProxy)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        // Username
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Username")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("username", text: $sipUsername)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        // Password
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Password")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                if showPassword {
                                    TextField("password", text: $sipPassword)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                } else {
                                    SecureField("password", text: $sipPassword)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
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
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                } else {
                    // Registration Status
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("Registered")
                                    .fontWeight(.medium)
                                Text(sipUsername + "@" + sipServer)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                
                // Call Section
                if pjsipManager.isRegistered {
                    VStack(spacing: 16) {
                        Text("Make Call")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        TextField("Phone Number or SIP URI", text: $phoneNumber)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.phonePad)
                        
                        // Current Call Info
                        if !pjsipManager.currentCall.isEmpty {
                            Text("Current Call: \(pjsipManager.currentCall)")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.vertical, 4)
                        }
                        
                        // Call Control Buttons
                        VStack(spacing: 12) {
                            // Make Call Button
                            Button(action: makeCall) {
                                HStack {
                                    Image(systemName: "phone.fill")
                                    Text("Call")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(phoneNumber.isEmpty || pjsipManager.callState != .idle)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            
                            // Answer Button (for incoming calls)
                            if pjsipManager.callState == .incoming {
                                Button(action: answerCall) {
                                    HStack {
                                        Image(systemName: "phone.fill")
                                        Text("Answer")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                            
                            // Hangup Button
                            if pjsipManager.callState == .calling ||
                               pjsipManager.callState == .connected ||
                               pjsipManager.callState == .incoming {
                                Button(action: hangupCall) {
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
                        
                        // Device Controls (similar to ViewController)
                        VStack(spacing: 12) {
                            Button(action: toggleMicrophone) {
                                Text("Microphone: \(pjsipManager.device.microphoneEnable ? "ON" : "OFF")")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            
                            Button(action: toggleSpeaker) {
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
                
                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationTitle("SIP Phone")
        .onAppear {
            setupSIP()
        }
    }
    
    // MARK: - Setup (similar to setupVCS in ViewController)
    
    private func setupSIP() {
        pjsipManager.printConsoleLog = true
        
        // Setup observers (similar to VCS.shared.observer)
        setupObservers()
    }
    
    private func setupObservers() {
        // Registration observers
        pjsipManager.observer.registration.onMessage = { state in
            print("SIP registration state: \(state.rawValue)")
            DispatchQueue.main.async {
                self.stateLabel = state.rawValue
            }
        }
        
        pjsipManager.observer.registration.onSuccess = {
            print("SIP registration successful")
            DispatchQueue.main.async {
                self.stateLabel = "Registration Successful"
            }
        }
        
        pjsipManager.observer.registration.onFailure = { state, reason in
            print("SIP registration failed: \(state.rawValue) - \(reason)")
            DispatchQueue.main.async {
                self.stateLabel = "\(state.rawValue): \(reason)"
            }
        }
        
        // Call observers
        pjsipManager.observer.call.onMessage = { state in
            print("SIP call state: \(state.rawValue)")
            DispatchQueue.main.async {
                self.stateLabel = state.rawValue
            }
        }
        
        pjsipManager.observer.call.onIncomingCall = { caller in
            print("Incoming call from: \(caller)")
            DispatchQueue.main.async {
                self.stateLabel = "Incoming call from: \(caller)"
            }
        }
        
        pjsipManager.observer.call.onCallConnected = {
            print("Call connected")
            DispatchQueue.main.async {
                self.stateLabel = "Call Connected"
            }
        }
        
        pjsipManager.observer.call.onCallEnded = {
            print("Call ended")
            DispatchQueue.main.async {
                self.stateLabel = "Call Ended"
            }
        }
        
        pjsipManager.observer.call.onFailure = { reason in
            print("Call failed: \(reason)")
            DispatchQueue.main.async {
                self.stateLabel = "Call Failed: \(reason)"
            }
        }
    }
    
    // MARK: - Actions
    
    private func registerWithSIP() {
        // Update manager configuration with user input
        pjsipManager.serverConfig.domain = sipServer
        pjsipManager.serverConfig.proxy = sipProxy
        pjsipManager.username = sipUsername
        pjsipManager.password = sipPassword
        
        // Configure user data (similar to VCS.shared.userData)
        pjsipManager.userData.updateValue(sipUsername, forKey: "UserID")
        pjsipManager.userData.updateValue(sipServer, forKey: "Server")
        
        // Call register with the configured values
        pjsipManager.registerAccount {}
    }
    
    private func unregister() {
        pjsipManager.unregister()
        stateLabel = "Unregistered"
    }
    
    private func makeCall() {
        pjsipManager.makeCall(to: phoneNumber) {}
    }
    
    private func answerCall() {
        pjsipManager.answerCall()
    }
    
    private func hangupCall() {
        pjsipManager.hangupCall()
        phoneNumber = ""
    }
    
    private func toggleMicrophone() {
        pjsipManager.device.microphoneEnable.toggle()
        // Apply microphone settings to PJSIP if needed
    }
    
    private func toggleSpeaker() {
        pjsipManager.device.speakerEnable.toggle()
        // Apply speaker settings to PJSIP if needed
    }
}
