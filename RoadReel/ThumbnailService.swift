import Foundation
import AVFoundation
import AppKit

private actor AsyncPermitPool {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = max(1, limit)
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSData>()
    private let limiter = AsyncPermitPool(limit: 2)
    private var inFlight: [String: Task<Data?, Never>] = [:]

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func imageData(for clip: TeslaClip) async -> Data? {
        let key = clip.id
        if let cached = cache.object(forKey: key as NSString) { return cached as Data }
        if let task = inFlight[key] { return await task.value }

        let thumbnailURL = clip.thumbnailURL
        let videoURL = clip.previewVideoURL
        let task = Task<Data?, Never> { [limiter] in
            await limiter.acquire()
            let data = await Self.loadImageData(thumbnailURL: thumbnailURL, videoURL: videoURL)
            await limiter.release()
            return data
        }
        inFlight[key] = task

        let data = await task.value
        inFlight[key] = nil
        if let data { cache.setObject(data as NSData, forKey: key as NSString, cost: data.count) }
        return data
    }

    private nonisolated static func loadImageData(thumbnailURL: URL?, videoURL: URL?) async -> Data? {
        if let thumbnailURL {
            return try? Data(contentsOf: thumbnailURL, options: [.mappedIfSafe])
        }
        guard let videoURL else { return nil }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        guard let (image, _) = try? await generator.image(
            at: CMTime(seconds: 1, preferredTimescale: 600)
        ) else { return nil }

        let representation = NSBitmapImageRep(cgImage: image)
        return representation.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }
}
