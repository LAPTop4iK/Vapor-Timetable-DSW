import App

@main
enum SyncRunnerMain {
    static func main() async throws {
        try await runSyncRunner()
    }
}
