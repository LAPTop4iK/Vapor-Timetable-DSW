import Vapor

/// DI-контейнер приложения.
/// Хранится один экземпляр на всё приложение.
/// unsafe? Нет: мы используем только неизменяемые ссылки + actor для кэша.
final class DIContainer: @unchecked Sendable {
    let appConfig: AppConfig
    let cacheStore: InMemoryCacheStore
    private var _firestoreService: FirestoreService?
    private let firestoreLock = NSLock()

    init(app: Application) {
        self.appConfig = AppConfig(from: app.environment)
        self.cacheStore = InMemoryCacheStore()
        self._firestoreService = nil
    }

    /// Get or create FirestoreService (lazy initialization with Request.client)
    func getFirestoreService(req: Request) -> FirestoreService? {
        // If not enabled, return nil
        guard appConfig.isFirestoreEnabled else {
            return nil
        }

        // Thread-safe lazy initialization
        firestoreLock.lock()
        defer { firestoreLock.unlock() }

        if let existing = _firestoreService {
            return existing
        }

        // Create new instance
        guard let projectId = appConfig.firestoreProjectId,
              let credentialsPath = appConfig.firestoreCredentialsPath else {
            req.logger.warning("Firestore is enabled but credentials not configured")
            return nil
        }

        do {
            let service = try FirestoreService(
                projectId: projectId,
                credentialsPath: credentialsPath,
                client: req.client,
                logger: req.logger
            )
            _firestoreService = service
            req.logger.info("Firestore service initialized in \(appConfig.backendMode.rawValue) mode")
            return service
        } catch {
            req.logger.error("Failed to initialize Firestore service: \(error)")
            return nil
        }
    }
    
    // фабрики сервисов (как было)
    func makeDSWClient(req: Request) -> any DSWClient {
        VaporDSWClient(client: req.client)
    }
    
    func makeParser(req: Request) -> any ScheduleParser {
        SwiftSoupScheduleParser(logger: req.logger)
    }
    
    func makeCachedTeacherDetailsProvider(req: Request) -> CachedTeacherDetailsService {
        let client = makeDSWClient(req: req)
        let parser = makeParser(req: req)
        let base = TeacherDetailsService(client: client, parser: parser)
        return CachedTeacherDetailsService(base: base, cache: cacheStore)
    }
    
    func makeCachedAggregationService(req: Request) -> CachedAggregationService {
        let client = makeDSWClient(req: req)
        let parser = makeParser(req: req)
        let teacherProvider = makeCachedTeacherDetailsProvider(req: req)
        
        let baseAgg = AggregationService(
            client: client,
            parser: parser,
            teacherService: teacherProvider,
            batchSize: 6
        )
        return CachedAggregationService(base: baseAgg, cache: cacheStore)
    }
    
    func makeCachedGroupScheduleService(req: Request) -> CachedGroupScheduleService {
        let client = makeDSWClient(req: req)
        let parser = makeParser(req: req)
        let base = GroupScheduleService(client: client, parser: parser)
        return CachedGroupScheduleService(base: base, cache: cacheStore)
    }
    
    func makeCachedGroupSearchService(req: Request) -> CachedGroupSearchService {
        let base = GroupSearchService(client: req.client)
        return CachedGroupSearchService(base: base, cache: cacheStore)
    }
    
    /// вот это новое:
    func cacheStats() async -> CacheStats {
        await cacheStore.stats()
    }
}

// остальное (Application.di, Request.di) без изменений
extension Application {
    private struct DIKey: StorageKey {
        typealias Value = DIContainer
    }
    
    var di: DIContainer {
        if let existing = self.storage[DIKey.self] {
            return existing
        } else {
            let new = DIContainer(app: self)
            self.storage[DIKey.self] = new
            return new
        }
    }
}

extension Request {
    var di: DIContainer { application.di }
}
