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
    @State private var sipServer = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isRegistering = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Registration Section
            if !pjsipManager.isRegistered {
                VStack {
                    Text("SIP Registration")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    TextField("SIP Server", text: $sipServer)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("Username", text: $username)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: registerWithSIP) {
                        if isRegistering {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Register")
                        }
                    }
                    .disabled(isRegistering || sipServer.isEmpty || username.isEmpty || password.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            } else {
                // Registration Status
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Registered as \(username)")
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
            }
            
            // Call Section
            if pjsipManager.isRegistered {
                VStack {
                    Text("Make Call")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    TextField("Phone Number or SIP URI", text: $phoneNumber)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.phonePad)
                    
                    // Call Status
                    Text("Status: \(callStateText)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !pjsipManager.currentCall.isEmpty {
                        Text("Current Call: \(pjsipManager.currentCall)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    // Call Control Buttons
                    HStack(spacing: 20) {
                        // Make Call Button
                        Button(action: makeCall) {
                            HStack {
                                Image(systemName: "phone.fill")
                                Text("Call")
                            }
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
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("SIP Phone")
    }
    
    // MARK: - Actions
    
    private func registerWithSIP() {
        isRegistering = true
        pjsipManager.register(server: sipServer, username: username, password: password)
        
        // Reset registering state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            isRegistering = false
        }
    }
    
    private func makeCall() {
        pjsipManager.makeCall(to: phoneNumber)
    }
    
    private func answerCall() {
        pjsipManager.answerCall()
    }
    
    private func hangupCall() {
        pjsipManager.hangupCall()
        phoneNumber = "" // Clear the number after hangup
    }
    
    // MARK: - Computed Properties
    
    private var callStateText: String {
        switch pjsipManager.callState {
        case .idle:
            return "Ready"
        case .calling:
            return "Calling..."
        case .incoming:
            return "Incoming Call"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Call Ended"
        }
    }
}
