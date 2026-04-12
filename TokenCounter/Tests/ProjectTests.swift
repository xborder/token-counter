import Testing
@testable import TokenCounter

struct ProjectTests {

    @Test func standardPath() {
        #expect(Project.deriveDisplayName(from: "-home-user-token-counter") == "token-counter")
    }

    @Test func rootPath() {
        #expect(Project.deriveDisplayName(from: "-root-my-project") == "my-project")
    }

    @Test func usersPath() {
        #expect(Project.deriveDisplayName(from: "-Users-charlie-code-my-app") == "code-my-app")
    }

    @Test func simpleName() {
        #expect(Project.deriveDisplayName(from: "project") == "project")
    }

    @Test func singleDash() {
        #expect(Project.deriveDisplayName(from: "-tmp-build") == "build")
    }
}
