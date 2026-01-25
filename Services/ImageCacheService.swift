import Foundation
import UIKit
import SwiftUI

/// Service for caching and loading profile images
/// Uses NSCache for memory and FileManager for disk persistence
actor ImageCacheService {
    static let shared = ImageCacheService()

    // MARK: - Private Properties

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private var loadingTasks: [String: Task<UIImage?, Never>] = [:]

    // MARK: - Init

    private init() {
        // Set up cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ProfileImages", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Configure memory cache
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    // MARK: - Public API

    /// Get an image from cache or load it from URL
    func image(for url: URL) async -> UIImage? {
        let key = cacheKey(for: url)

        // Check memory cache first
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        // Check if already loading
        if let existingTask = loadingTasks[key] {
            return await existingTask.value
        }

        // Load from network
        let task = Task<UIImage?, Never> {
            await loadFromNetwork(url: url, key: key)
        }
        loadingTasks[key] = task

        let result = await task.value
        loadingTasks.removeValue(forKey: key)

        return result
    }

    /// Get an image for a CloudKit asset ID
    func image(forAssetId assetId: String) async -> UIImage? {
        let key = "asset_\(assetId)"

        // Check memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        // Would need to fetch from CloudKit - handled by CloudKitService
        return nil
    }

    /// Cache an image with a specific key
    func cache(_ image: UIImage, forKey key: String) {
        memoryCache.setObject(image, forKey: key as NSString)
        saveToDisk(image: image, key: key)
    }

    /// Cache an image from data with a specific key
    func cache(_ imageData: Data, forKey key: String) {
        guard let image = UIImage(data: imageData) else { return }
        cache(image, forKey: key)
    }

    /// Preload images for a list of users
    func preloadImages(for assetIds: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for assetId in assetIds {
                group.addTask {
                    _ = await self.image(forAssetId: assetId)
                }
            }
        }
    }

    /// Clear all cached images
    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Clear a specific image from cache
    func clearImage(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: - Private Helpers

    private func cacheKey(for url: URL) -> String {
        url.absoluteString.data(using: .utf8)?.base64EncodedString() ?? url.lastPathComponent
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(image: UIImage, key: String) {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: fileURL)
    }

    private func loadFromNetwork(url: URL, key: String) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                return nil
            }

            // Cache the loaded image
            memoryCache.setObject(image, forKey: key as NSString)
            saveToDisk(image: image, key: key)

            return image
        } catch {
            print("[ImageCache] Failed to load image from \(url): \(error)")
            return nil
        }
    }
}

// MARK: - SwiftUI AsyncImage Alternative

/// A view that displays an image loaded from cache or network
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder()
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url, !isLoading else { return }
        isLoading = true
        image = await ImageCacheService.shared.image(for: url)
        isLoading = false
    }
}

/// Convenience initializer with default placeholder
extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: URL?) {
        self.init(url: url) {
            ProgressView()
        }
    }
}

// MARK: - Profile Photo View

/// A circular profile photo view with caching
struct ProfilePhotoView: View {
    let assetId: String?
    let emoji: String
    let size: CGFloat
    let isOnline: Bool

    @State private var image: UIImage?

    init(assetId: String?, emoji: String, size: CGFloat = 60, isOnline: Bool = true) {
        self.assetId = assetId
        self.emoji = emoji
        self.size = size
        self.isOnline = isOnline
    }

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Fallback to emoji
                Text(emoji)
                    .font(.system(size: size * 0.5))
                    .frame(width: size, height: size)
                    .background(isOnline ? Color.purple.opacity(0.2) : Color.gray.opacity(0.2))
                    .clipShape(Circle())
            }
        }
        .overlay(
            Circle()
                .stroke(isOnline ? Color.purple : Color.gray, lineWidth: 2)
        )
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let assetId = assetId, !assetId.isEmpty else { return }
        image = await ImageCacheService.shared.image(forAssetId: assetId)
    }
}

// MARK: - Image Resizing

extension UIImage {
    /// Resize image to fit within max dimension while maintaining aspect ratio
    func resized(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let ratio = max(size.width, size.height) / maxDimension
        if ratio <= 1 { return self }

        let newSize = CGSize(
            width: size.width / ratio,
            height: size.height / ratio
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Create a thumbnail
    func thumbnail(dimension: CGFloat) -> UIImage {
        let ratio = min(dimension / size.width, dimension / size.height)
        let newSize = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dimension, height: dimension))
        return renderer.image { _ in
            let origin = CGPoint(
                x: (dimension - newSize.width) / 2,
                y: (dimension - newSize.height) / 2
            )
            draw(in: CGRect(origin: origin, size: newSize))
        }
    }
}
