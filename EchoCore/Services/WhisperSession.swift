import Foundation
import os.log
@preconcurrency import WhisperKit

/// A shared, reference-counted WhisperKit model manager so multiple services
/// (AutoAlignmentService, ContinuousAlignmentService, etc.) share a single
/// in-memory model instance instead of each loading their own ~40 MB copy.
///
/// Usage:
///   let session = WhisperSession.shared
///   let wk = try await session.acquire(model: "base.en")
///   defer { await session.release() }
///   let result = await wk.transcribe(...)
@MainActor
final class WhisperSession {
    static let shared = WhisperSession()

    private let logger = Logger(category: "WhisperSession")

    private var cachedModel: WhisperKit?
    private var modelSize: String?
    private var retainCount: Int = 0
    private var generation: Int = 0

    private init() {}

    /// Acquires a reference to the WhisperKit model, loading it if necessary.
    /// Callers **must** call `release()` when done to allow unloading.
    func acquire(model: String = "base.en") async throws -> WhisperKit {
        retainCount += 1
        generation &+= 1
        if let cached = cachedModel, modelSize == model {
            logger.debug("WhisperSession: reusing cached '\(model)' (retainCount=\(self.retainCount))")
            return cached
        }
        logger.info("WhisperSession: loading '\(model)' (retainCount=\(self.retainCount))")
        let wk = try await WhisperKit(model: model)
        cachedModel = wk
        modelSize = model
        return wk
    }

    /// Releases one reference.  When the retain count reaches zero the model
    /// is unloaded to free ~40 MB of memory.
    ///
    /// A generation counter prevents a race where `acquire()` stores a fresh
    /// model but a previously-spawned unload `Task` fires afterward and
    /// nil-s out the reference.
    func release() {
        retainCount = max(0, retainCount - 1)
        if retainCount == 0 {
            logger.info("WhisperSession: retainCount=0, unloading model")
            let capturedGeneration = generation
            Task {
                // If acquire() was called again between this Task's creation
                // and execution, generation will have advanced — don't nil out
                // the freshly-loaded model.
                guard self.generation == capturedGeneration else { return }
                await cachedModel?.unloadModels()
                cachedModel = nil
                modelSize = nil
            }
        } else {
            logger.debug("WhisperSession: release (retainCount=\(self.retainCount))")
        }
    }

    /// Force-unloads the model regardless of retain count. Use when the
    /// audiobook changes or alignment is cancelled.
    func forceUnload() {
        retainCount = 0
        generation &+= 1
        Task {
            let capturedGeneration = generation
            guard self.generation == capturedGeneration else { return }
            await cachedModel?.unloadModels()
            cachedModel = nil
            modelSize = nil
        }
    }
}
