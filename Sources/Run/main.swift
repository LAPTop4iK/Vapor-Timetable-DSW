import App

@main
enum Main {
    static func main() async throws {
        try await Entrypoint.main()
    }
}
