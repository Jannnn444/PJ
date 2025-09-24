//
//  PJSIPTest.swift
//  PJSIP2
//
//  Created by Hualiteq International on 2025/9/24.
//

import Foundation

class PJSIPTest {
    func testIntegration() {
        print("Testing PJSIP manual integration...")
        
        let status = pjsua_create()
        print("pjsua_create() status: \(status)")
        
        if status == 0 {  // PJ_SUCCESS = 0
            print("✅ PJSIP created successfully!")
            
            var cfg = pjsua_config()
            pjsua_config_default(&cfg)
            print("✅ Config initialized!")
            
            // Test that constants are available
            let invalidId: pjsua_acc_id = PJSUA_INVALID_ID.rawValue
            print("✅ PJSUA_INVALID_ID = \(invalidId)")
            
            pjsua_destroy()
            print("✅ PJSIP destroyed!")
        } else {
            print("❌ PJSIP creation failed!")
        }
    }
}


//let test = PJSIPTest()
//test.testIntegration()


