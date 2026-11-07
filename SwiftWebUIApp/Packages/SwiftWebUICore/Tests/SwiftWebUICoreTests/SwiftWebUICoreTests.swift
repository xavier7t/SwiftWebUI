import Testing
@testable import SwiftWebUICore

@Test func versionIsSet() {
    #expect(!SwiftWebUICore.version.isEmpty)
}
