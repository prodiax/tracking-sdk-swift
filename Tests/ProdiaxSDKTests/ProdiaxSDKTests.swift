import XCTest
@testable import ProdiaxSDK

final class ProdiaxSDKTests: XCTestCase {
    
    func testSDKInitialization() throws {
        let config = ProdiaxConfig(
            productId: "test-product-id",
            debugMode: true
        )
        
        ProdiaxSDK.shared.initialize(config: config)
        
        // Test that SDK is initialized
        XCTAssertNotNil(ProdiaxSDK.shared.getSession())
    }
    
    func testEventTracking() throws {
        let config = ProdiaxConfig(
            productId: "test-product-id",
            debugMode: true
        )
        
        ProdiaxSDK.shared.initialize(config: config)
        
        // Test event tracking
        ProdiaxSDK.shared.track("test_event", properties: ["key": "value"])
        
        // Test screen tracking
        ProdiaxSDK.shared.trackScreen("test_screen", screenTitle: "Test Screen")
        
        // Test user identification
        ProdiaxSDK.shared.identify("test_user", traits: ["email": "test@example.com"])
    }
    
    func testSessionManagement() throws {
        let config = ProdiaxConfig(
            productId: "test-product-id",
            debugMode: true
        )
        
        ProdiaxSDK.shared.initialize(config: config)
        
        let session = ProdiaxSDK.shared.getSession()
        XCTAssertNotNil(session)
        XCTAssertNotNil(session?["session_id"])
    }
}
