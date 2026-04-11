import XCTest
@testable import TokenCounter

final class ProjectTests: XCTestCase {

    func testDeriveDisplayName_standardPath() {
        let name = Project.deriveDisplayName(from: "-home-user-token-counter")
        XCTAssertEqual(name, "token-counter")
    }

    func testDeriveDisplayName_rootPath() {
        let name = Project.deriveDisplayName(from: "-root-my-project")
        XCTAssertEqual(name, "my-project")
    }

    func testDeriveDisplayName_usersPath() {
        let name = Project.deriveDisplayName(from: "-Users-charlie-code-my-app")
        XCTAssertEqual(name, "code-my-app")
    }

    func testDeriveDisplayName_simpleName() {
        let name = Project.deriveDisplayName(from: "project")
        XCTAssertEqual(name, "project")
    }

    func testDeriveDisplayName_singleDash() {
        let name = Project.deriveDisplayName(from: "-tmp-build")
        XCTAssertEqual(name, "build")
    }
}
