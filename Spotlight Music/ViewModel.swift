import Foundation
import AVFoundation
import MediaPlayer
import AppKit

// Concurrency-friendly semaphore for async contexts (Swift 6-safe)
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(value: Int) { self.permits = value }
    
    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }
    
    func release() {
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
        } else {
            permits += 1
        }
    }
}

extension NSImage {
    func resized(to newSize: NSSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize))
        newImage.unlockFocus()
        return newImage
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var songs: [SongItem] = []
    @Published var albums: [AlbumItem] = []
    @Published var artists: [ArtistItem] = []
    @Published var videos: [VideoItem] = []
    @Published var isSearching: Bool = false
    @Published var nowPlaying: SongItem?
    @Published var errorMessage: String?
    @Published var favoriteSongs: [SongItem] = []
    
    // Cache for search results to reduce energy usage
    private var searchCache: [String: SearchAllResponse] = [:]
    private let maxCacheSize = 20
    
    // Limit concurrent network requests to save energy (Swift 6-safe)
    private let networkLimiter = AsyncSemaphore(value: 2)
    
    // Detail view states
    @Published var selectedAlbum: AlbumItem?
    @Published var selectedArtist: ArtistItem?
    @Published var albumSongs: [SongItem] = []
    @Published var artistSongs: [SongItem] = []
    @Published var artistAlbums: [AlbumItem] = []
    @Published var isLoadingDetails: Bool = false
    
    // Playlist context for auto-play
    private var currentPlaylist: [SongItem] = []
    private var currentPlaylistIndex: Int = -1
    private var isPlayingFromPlaylist: Bool = false

    private var player: AVPlayer?
    private var searchTask: Task<Void, Never>?
    private var timeObserverToken: Any?
    private var endObserverToken: Any?
    private var didTriggerEndForCurrentItem: Bool = false
    private var remoteCommandsConfigured = false

    // Public access to player for pause/resume functionality
    var currentPlayer: AVPlayer? { player }
    
    // Add methods to manually trigger next/previous for better integration
    func playNext() {
        playNextTrack()
    }
    
    func playPrevious() {
        playPreviousTrack()
    }
    
    // URGENT: Manual auto-play trigger for testing
    func testAutoPlay() {
        print("🔥 MANUAL AUTO-PLAY TEST TRIGGERED")
        handleSongEnded()
    }
    
    // Force auto-play test regardless of settings
    func forceTestAutoPlay() {
        print("🚨 FORCE AUTO-PLAY TEST - BYPASSING SETTINGS")
        
        guard let currentSong = nowPlaying else {
            print("❌ No current song to test auto-play")
            return
        }
        
        print("🎵 Force testing with current song: \(currentSong.title)")
        
        // Force find next song
        if let nextSong = findNextSongSimple(for: currentSong) {
            print("✅ Force test found next song: \(nextSong.title)")
            // Just play the next song directly
            play(song: nextSong)
        } else {
            print("❌ Force test could not find next song")
        }
    }
    
    // Enhanced auto-play test with extraction method validation
    func testAutoPlayWithExtraction() {
        print("🔥 === ENHANCED AUTO-PLAY TEST WITH EXTRACTION ===")
        
        guard let currentSong = nowPlaying else {
            print("❌ No current song to test auto-play")
            return
        }
        
        print("🎵 Testing with current song: \(currentSong.title)")
        print("🔍 Available contexts:")
        print("  - Album songs: \(albumSongs.count)")
        print("  - Artist songs: \(artistSongs.count)")
        print("  - Search results: \(songs.count)")
        print("  - Videos: \(videos.count)")
        print("  - Favorites: \(favoriteSongs.count)")
        print("🞯 Current playlist: \(currentPlaylist.count) songs, index \(currentPlaylistIndex)")
        
        // Test next song finding
        if let nextSong = findNextSongSimple(for: currentSong) {
            print("✅ Next song found: \(nextSong.title)")
            
            // Test extraction for the next song
            Task {
                print("🔄 Testing extraction for next song...")
                do {
                    let json = try await runHelper(arguments: ["stream_url", nextSong.id])
                    if let urlString = json["stream_url"] as? String {
                        print("✅ Extraction test successful for next song: \(urlString.prefix(50))...")
                        
                        // Now trigger the actual auto-play
                        await MainActor.run {
                            self.handleSongEnded()
                        }
                    } else if let error = json["error"] as? String {
                        print("⚠️ Extraction test failed: \(error)")
                        print("🔄 Trying web-based extraction...")
                        
                        if let webURL = await self.extractStreamURLFromWeb(videoId: nextSong.id) {
                            print("✅ Web extraction test successful: \(webURL.prefix(50))...")
                            await MainActor.run {
                                self.handleSongEnded()
                            }
                        } else {
                            print("❌ Both extraction methods failed for next song")
                        }
                    }
                } catch {
                    print("❌ Extraction test error: \(error)")
                }
            }
        } else {
            print("❌ No next song found for auto-play test")
        }
        
        print("🔥 === END ENHANCED AUTO-PLAY TEST ===")
    }
    
    // New method to test next/previous functionality
    func debugPlaylistContext() {
        guard let nowPlayingSong = nowPlaying else {
            print("❌ No song currently playing")
            return
        }
        
        print("🎵 Current Song: \(nowPlayingSong.title)")
        print("🎯 Playlist Context:")
        print("  - isPlayingFromPlaylist: \(isPlayingFromPlaylist)")
        print("  - currentPlaylist count: \(currentPlaylist.count)")
        print("  - currentPlaylistIndex: \(currentPlaylistIndex)")
        
        print("📋 Available Lists:")
        print("  - songs: \(songs.count)")
        print("  - albumSongs: \(albumSongs.count)")
        print("  - artistSongs: \(artistSongs.count)")
        print("  - videos: \(videos.count)")
        print("  - favoriteSongs: \(favoriteSongs.count)")
        
        if let nextSong = findNextSongSimple(for: nowPlayingSong) {
            print("✅ Next song available: \(nextSong.title)")
        } else {
            print("❌ No next song found")
        }
        
        if let previousSong = findPreviousSong(for: nowPlayingSong) {
            print("✅ Previous song available: \(previousSong.title)")
        } else {
            print("❌ No previous song found")
        }
    }

    // MARK: - Python environment bootstrap without venv
    private func sitePackagesPath() -> String {
        let fm = FileManager.default
        let baseURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = baseURL.appendingPathComponent("SpotlightMusic", isDirectory: true)
        let siteDir = appDir.appendingPathComponent("python-site", isDirectory: true)
        return siteDir.path
    }

    private func selectPythonExec() -> String? {
        let fm = FileManager.default
        // Prefer bundled Python if provided
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("BundledPython/bin/python3").path,
           fm.isExecutableFile(atPath: bundled) { return bundled }
        let env = ProcessInfo.processInfo.environment
        let candidates = [
            env["PYTHON_EXEC"],
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/usr/bin/python3"
        ].compactMap { $0 }
        for p in candidates { if fm.isExecutableFile(atPath: p) { return p } }
        return nil
    }

    private let ytDlpUpdateKey = "ytDlpLastUpdated"
    private let ytDlpUpdateInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    
    private func ensurePythonSiteInstalled() async {
        let fm = FileManager.default
        guard let python = selectPythonExec() else {
            await MainActor.run { self.errorMessage = "Python 3 not found. Please install Python 3 or bundle it with the app." }
            return
        }
        let siteDir = sitePackagesPath()
        try? fm.createDirectory(atPath: siteDir, withIntermediateDirectories: true)

        // Check if modules can import when PYTHONPATH includes siteDir
        func modulesReady() async -> Bool {
            let code = "import sys; sys.path.insert(0, r'\(siteDir)'); import ytmusicapi, yt_dlp; print('OK')"
            let (_, out, _) = (try? await runProcess(exec: python, args: ["-c", code])) ?? (1, "", "")
            return out.contains("OK")
        }
        
        // If modules are already ready, check if we need to update yt-dlp
        if await modulesReady() {
            await updateYtDlpIfNeeded()
            return
        }

        // Try to ensure pip exists
        _ = try? await runProcess(exec: python, args: ["-m", "ensurepip", "--upgrade"]) 

        // Install/upgrade packages with better error handling
        let packagesToInstall = [
            "yt-dlp>=2024.8.6",  // Ensure recent version
            "ytmusicapi>=1.7.0"   // Ensure recent version
        ]
        
        // Prefer offline wheels from bundle
        if let wheelsDir = Bundle.main.resourceURL?.appendingPathComponent("PythonWheels").path,
           fm.fileExists(atPath: wheelsDir) {
            for package in packagesToInstall {
                _ = try? await runProcess(exec: python, args: ["-m", "pip", "install", "--no-index", "--find-links", wheelsDir, "--target", siteDir, "--upgrade", package]) 
            }
        } else {
            // Online installation with upgrade
            for package in packagesToInstall {
                _ = try? await runProcess(exec: python, args: ["-m", "pip", "install", "--target", siteDir, "--upgrade", package]) 
            }
        }
        
        // Mark yt-dlp as updated after fresh installation
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: ytDlpUpdateKey)
    }
    
    private func updateYtDlpIfNeeded() async {
        // Check if we've updated yt-dlp recently
        let lastUpdated = UserDefaults.standard.double(forKey: ytDlpUpdateKey)
        let now = Date().timeIntervalSince1970
        
        // Only update if it's been more than 24 hours since last update or never updated
        guard lastUpdated == 0 || (now - lastUpdated) > ytDlpUpdateInterval else {
            print("yt-dlp recently updated, skipping automatic update")
            return
        }
        
        guard let python = selectPythonExec() else { return }
        let siteDir = sitePackagesPath()
        
        // Check yt-dlp version
        let versionCode = "import sys; sys.path.insert(0, r'\(siteDir)'); import yt_dlp; print(yt_dlp.version.__version__)"
        let (_, versionOut, _) = (try? await runProcess(exec: python, args: ["-c", versionCode])) ?? (1, "", "")
        
        print("Current yt-dlp version: \(versionOut.trimmingCharacters(in: .whitespacesAndNewlines))")
        print("Updating yt-dlp to latest version (first run or 24h interval)...")
        
        let result = (try? await runProcess(exec: python, args: ["-m", "pip", "install", "--target", siteDir, "--upgrade", "yt-dlp"])) ?? (1, "", "")
        let exitCode = result.0
        
        // Only mark as updated if the update was successful
        if exitCode == 0 {
            UserDefaults.standard.set(now, forKey: ytDlpUpdateKey)
            print("yt-dlp update completed successfully")
        } else {
            print("yt-dlp update failed, will retry on next run")
        }
    }
    
    // Method to force update yt-dlp when extraction failures occur
    private func forceUpdateYtDlp() async {
        guard let python = selectPythonExec() else { return }
        let siteDir = sitePackagesPath()
        
        print("Forcing yt-dlp update due to extraction failure...")
        let result = (try? await runProcess(exec: python, args: ["-m", "pip", "install", "--target", siteDir, "--upgrade", "--force-reinstall", "yt-dlp"])) ?? (1, "", "")
        let exitCode = result.0
        
        if exitCode == 0 {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: ytDlpUpdateKey)
            print("Force update completed successfully")
        } else {
            print("Force update failed")
        }
    }

    func performSetupForPython() async {
        await ensurePythonSiteInstalled()
        loadFavorites()
    }

    // MARK: - Favorites
    private let favoritesKey = "favoriteSongs.v1"
    func toggleFavorite(_ song: SongItem) {
        if let idx = favoriteSongs.firstIndex(where: { $0.id == song.id }) {
            favoriteSongs.remove(at: idx)
            
            // If we're currently playing from favorites and this was the current song, update playlist context
            if isPlayingFromPlaylist && currentPlaylist.count == favoriteSongs.count + 1 {
                // Likely playing from favorites, refresh the context
                if let nowPlayingSong = nowPlaying, nowPlayingSong.id != song.id {
                    // Update the playlist to reflect the removal
                    currentPlaylist = favoriteSongs
                    if let newIndex = favoriteSongs.firstIndex(where: { $0.id == nowPlayingSong.id }) {
                        currentPlaylistIndex = newIndex
                        print("Updated favorites playlist context after removal: index \(newIndex) of \(favoriteSongs.count)")
                    }
                }
            }
        } else {
            favoriteSongs.insert(song, at: 0)
            
            // If we're currently playing from favorites, update playlist context
            if isPlayingFromPlaylist && currentPlaylist.count == favoriteSongs.count - 1 {
                // Likely playing from favorites, refresh the context
                if let nowPlayingSong = nowPlaying {
                    // Update the playlist to reflect the addition
                    currentPlaylist = favoriteSongs
                    if let newIndex = favoriteSongs.firstIndex(where: { $0.id == nowPlayingSong.id }) {
                        currentPlaylistIndex = newIndex
                        print("Updated favorites playlist context after addition: index \(newIndex) of \(favoriteSongs.count)")
                    }
                }
            }
        }
        saveFavorites()
    }
    func isFavorite(_ song: SongItem) -> Bool { favoriteSongs.contains(where: { $0.id == song.id }) }
    
    // MARK: - Favorites Reordering
    func moveFavoriteUp(_ song: SongItem) {
        guard let currentIndex = favoriteSongs.firstIndex(where: { $0.id == song.id }),
              currentIndex > 0 else { return }
        
        let newIndex = currentIndex - 1
        let movedSong = favoriteSongs.remove(at: currentIndex)
        favoriteSongs.insert(movedSong, at: newIndex)
        
        // Update playlist context if currently playing from favorites
        updatePlaylistContextAfterReorder()
        saveFavorites()
    }
    
    func moveFavoriteDown(_ song: SongItem) {
        guard let currentIndex = favoriteSongs.firstIndex(where: { $0.id == song.id }),
              currentIndex < favoriteSongs.count - 1 else { return }
        
        let newIndex = currentIndex + 1
        let movedSong = favoriteSongs.remove(at: currentIndex)
        favoriteSongs.insert(movedSong, at: newIndex)
        
        // Update playlist context if currently playing from favorites
        updatePlaylistContextAfterReorder()
        saveFavorites()
    }
    
    // Convenience methods that take videoId
    func moveFavoriteUp(videoId: String) {
        guard let song = favoriteSongs.first(where: { $0.id == videoId }) else { return }
        moveFavoriteUp(song)
    }
    
    func moveFavoriteDown(videoId: String) {
        guard let song = favoriteSongs.first(where: { $0.id == videoId }) else { return }
        moveFavoriteDown(song)
    }
    
    private func updatePlaylistContextAfterReorder() {
        // Update playlist context if currently playing from favorites
        if isPlayingFromPlaylist && currentPlaylist.count == favoriteSongs.count,
           let nowPlayingSong = nowPlaying,
           let newIndex = favoriteSongs.firstIndex(where: { $0.id == nowPlayingSong.id }) {
            currentPlaylist = favoriteSongs
            currentPlaylistIndex = newIndex
            print("Updated favorites playlist context after reorder: index \(newIndex) of \(favoriteSongs.count)")
        }
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favoriteSongs) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey),
              let list = try? JSONDecoder().decode([SongItem].self, from: data) else { return }
        favoriteSongs = list
    }

    private func runProcess(exec: String, args: [String]) async throws -> (Int32, String, String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: exec)
            process.arguments = args
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            do { try process.run() } catch { continuation.resume(throwing: error); return }
            process.terminationHandler = { _ in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: (process.terminationStatus, o, e))
            }
        }
    }

    func updateQuery(_ newQuery: String) {
        query = newQuery
        debouncedSearch()
    }

    func debouncedSearch() {
        searchTask?.cancel()
        let currentQuery = query
        searchTask = Task { [weak self] in
            // Increase debounce time to reduce energy usage from frequent searches
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSearch(currentQuery)
        }
    }

    // MARK: - Context Management
    
    /// Updates the playlist context when the currently playing song might have moved to a different category
    private func updatePlaylistContextIfNeeded() {
        guard let nowPlayingSong = nowPlaying else { return }
        
        print("🔄 Checking if playlist context needs updating for: \(nowPlayingSong.title)")
        
        // If we're currently playing from a saved playlist, check if it's still valid
        if isPlayingFromPlaylist && !currentPlaylist.isEmpty {
            // Check if current song is still in the saved playlist at the expected index
            if currentPlaylistIndex >= 0 && currentPlaylistIndex < currentPlaylist.count {
                let expectedSong = currentPlaylist[currentPlaylistIndex]
                if expectedSong.id == nowPlayingSong.id {
                    print("✅ Saved playlist context is still valid")
                    return
                }
            }
        }
        
        // Saved context is invalid, try to find the song in current data
        if let albumIndex = albumSongs.firstIndex(where: { $0.id == nowPlayingSong.id }) {
            currentPlaylist = albumSongs
            currentPlaylistIndex = albumIndex
            isPlayingFromPlaylist = true
            print("🎧 Updated to album context: index \(albumIndex) of \(albumSongs.count)")
        } else if let artistIndex = artistSongs.firstIndex(where: { $0.id == nowPlayingSong.id }) {
            currentPlaylist = artistSongs
            currentPlaylistIndex = artistIndex
            isPlayingFromPlaylist = true
            print("🎤 Updated to artist context: index \(artistIndex) of \(artistSongs.count)")
        } else if let searchIndex = songs.firstIndex(where: { $0.id == nowPlayingSong.id }) {
            currentPlaylist = songs
            currentPlaylistIndex = searchIndex
            isPlayingFromPlaylist = true
            print("🔍 Updated to search context: index \(searchIndex) of \(songs.count)")
        } else if let favoriteIndex = favoriteSongs.firstIndex(where: { $0.id == nowPlayingSong.id }) {
            currentPlaylist = favoriteSongs
            currentPlaylistIndex = favoriteIndex
            isPlayingFromPlaylist = true
            print("❤️ Updated to favorites context: index \(favoriteIndex) of \(favoriteSongs.count)")
        } else {
            // Song not found in any current list
            isPlayingFromPlaylist = false
            currentPlaylist = []
            currentPlaylistIndex = -1
            print("❌ No valid context found, cleared playlist context")
        }
    }

    func performSearch(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // IMPORTANT: Clear detail views when search is cleared to return to main view
            clearDetails()
            self.songs = []
            self.albums = []
            self.artists = []
            self.videos = []
            return
        }
        
        // IMPORTANT: Clear detail views when performing search to return to main search results
        // This ensures that if user is on album/artist page and searches, they see search results
        clearDetails()
        
        // Check cache first to save energy
        if let cachedResult = searchCache[trimmed] {
            self.songs = cachedResult.songs
            self.albums = cachedResult.albums
            self.artists = cachedResult.artists
            self.videos = cachedResult.videos
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        
        // Limit concurrent network requests to save energy (Swift 6-safe)
        await networkLimiter.acquire()
        defer { Task { await networkLimiter.release() } }
        
        do {
            let resp = try await runHelper(arguments: ["search_all", trimmed])
            if let error = resp["error"] as? String {
                self.errorMessage = error
                self.songs = []
                self.albums = []
                self.artists = []
                self.videos = []
                return
            }
            if let data = try? JSONSerialization.data(withJSONObject: resp, options: []),
               let decoded = try? JSONDecoder().decode(SearchAllResponse.self, from: data) {
                self.songs = decoded.songs
                self.albums = decoded.albums
                self.artists = decoded.artists
                self.videos = decoded.videos
                
                // Update playlist context if current song might be in new results
                self.updatePlaylistContextIfNeeded()
                
                // Cache the result to save energy on future searches
                cacheSearchResult(query: trimmed, result: decoded)
            } else {
                self.songs = []
                self.albums = []
                self.artists = []
                self.videos = []
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.songs = []
            self.albums = []
            self.artists = []
            self.videos = []
        }
    }
    
    private func cacheSearchResult(query: String, result: SearchAllResponse) {
        // Limit cache size to prevent memory bloat
        if searchCache.count >= maxCacheSize {
            // Remove oldest entry
            if let firstKey = searchCache.keys.first {
                searchCache.removeValue(forKey: firstKey)
            }
        }
        searchCache[query] = result
    }

    func play(song: SongItem) {
        play(song: song, fromPlaylist: nil, atIndex: -1)
    }
    
    func play(video: VideoItem) {
        // Convert video to song format for playback
        let songItem = songItem(from: video)
        play(song: songItem)
    }
    
    func play(video: VideoItem, fromPlaylist playlist: [VideoItem], atIndex index: Int) {
        // Map video playlist to song playlist for unified playback handling
        let mappedPlaylist = playlist.map { songItem(from: $0) }
        let currentSong = songItem(from: video)
        play(song: currentSong, fromPlaylist: mappedPlaylist, atIndex: index)
    }

    private func songItem(from video: VideoItem) -> SongItem {
        return SongItem(
            id: video.id,
            title: video.title,
            artists: video.artists,
            album: nil,
            duration: video.duration,
            thumbnail: video.thumbnail
        )
    }
    
    // MARK: - Web-based Stream Extraction
    private func extractStreamURLFromWeb(videoId: String) async -> String? {
        // Try multiple web-based extraction methods
        
        // Method 1: YouTube embed page
        if let url = await tryYouTubeEmbed(videoId: videoId) {
            return url
        }
        
        // Method 2: YouTube watch page
        if let url = await tryYouTubeWatchPage(videoId: videoId) {
            return url
        }
        
        // Method 3: Try alternative video info API
        if let url = await tryVideoInfoAPI(videoId: videoId) {
            return url
        }
        
        return nil
    }
    
    private func tryYouTubeEmbed(videoId: String) async -> String? {
        do {
            let embedURL = URL(string: "https://www.youtube.com/embed/\(videoId)")!
            var request = URLRequest(url: embedURL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""
            
            // Try to extract ytInitialPlayerResponse
            return extractPlayerResponse(from: html)
        } catch {
            print("YouTube embed extraction failed: \(error)")
            return nil
        }
    }
    
    private func tryYouTubeWatchPage(videoId: String) async -> String? {
        do {
            let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
            var request = URLRequest(url: watchURL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""
            
            return extractPlayerResponse(from: html)
        } catch {
            print("YouTube watch page extraction failed: \(error)")
            return nil
        }
    }
    
    private func tryVideoInfoAPI(videoId: String) async -> String? {
        do {
            // Try the get_video_info endpoint (may be deprecated but sometimes still works)
            let infoURL = URL(string: "https://www.youtube.com/get_video_info?video_id=\(videoId)")!
            var request = URLRequest(url: infoURL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = String(data: data, encoding: .utf8) ?? ""
            
            // Parse URL-encoded response
            var components = URLComponents()
            components.query = response
            let queryItems = components.queryItems ?? []
            
            for item in queryItems {
                if item.name == "player_response", 
                   let value = item.value,
                   let data = value.data(using: .utf8),
                   let playerResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return extractStreamURL(from: playerResponse)
                }
            }
        } catch {
            print("Video info API extraction failed: \(error)")
        }
        return nil
    }
    
    private func extractPlayerResponse(from html: String) -> String? {
        // Try multiple patterns for player response
        let patterns = [
            "ytInitialPlayerResponse\\s*=\\s*(\\{.+?\\});",
            "var\\s+ytInitialPlayerResponse\\s*=\\s*(\\{.+?\\});",
            "window\\[\"ytInitialPlayerResponse\"\\]\\s*=\\s*(\\{.+?\\});"
        ]
        
        for pattern in patterns {
            if let range = html.range(of: pattern, options: .regularExpression) {
                let match = String(html[range])
                if let jsonStart = match.firstIndex(of: "{") {
                    let jsonString = String(match[jsonStart...])
                        .replacingOccurrences(of: ";$", with: "", options: .regularExpression)
                    
                    if let jsonData = jsonString.data(using: .utf8),
                       let playerResponse = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        return extractStreamURL(from: playerResponse)
                    }
                }
            }
        }
        return nil
    }
    
    private func extractStreamURL(from playerResponse: [String: Any]) -> String? {
        guard let streamingData = playerResponse["streamingData"] as? [String: Any] else {
            return nil
        }
        
        // Try adaptive formats first (audio-only preferred)
        if let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] {
            // Sort audio formats by bitrate (highest first)
            let audioFormats = adaptiveFormats.filter { format in
                if let mimeType = format["mimeType"] as? String {
                    return mimeType.hasPrefix("audio/")
                }
                return false
            }.sorted { format1, format2 in
                let bitrate1 = format1["bitrate"] as? Int ?? format1["averageBitrate"] as? Int ?? 0
                let bitrate2 = format2["bitrate"] as? Int ?? format2["averageBitrate"] as? Int ?? 0
                return bitrate1 > bitrate2
            }
            
            for format in audioFormats {
                if let url = format["url"] as? String {
                    return url
                }
            }
        }
        
        // Fallback to regular formats
        if let formats = streamingData["formats"] as? [[String: Any]] {
            for format in formats {
                if let url = format["url"] as? String {
                    return url
                }
            }
        }
        
        return nil
    }
    
    func play(song: SongItem, fromPlaylist playlist: [SongItem]?, atIndex index: Int) {
        // Stop current playback immediately
        player?.pause()
        
        // Update UI state immediately for instant feedback
        print("🎵 Playing: \(song.title)")
        nowPlaying = song
        
        // Simple context management
        if let playlist = playlist {
            currentPlaylist = playlist
            currentPlaylistIndex = index
            isPlayingFromPlaylist = true
            print("🎯 Set playlist context: \(playlist.count) songs, index \(index)")
        } else {
            // Try to auto-detect context if not provided
            isPlayingFromPlaylist = false
            currentPlaylist = []
            currentPlaylistIndex = -1
            print("🚐 No playlist context - playing single song")
        }
        
        // Clean up previous observers immediately
        if let token = timeObserverToken, let existing = player {
            existing.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let endToken = endObserverToken {
            NotificationCenter.default.removeObserver(endToken)
            endObserverToken = nil
        }
        
        // Set loading state in now playing
        MPNowPlayingInfoCenter.default().playbackState = .interrupted
        
        Task {
            var streamURL: URL?
            var errorMsg: String?
            var retryCount = 0
            let maxRetries = 1 // Keep it simple
            
            // Simple extraction with one retry
            while streamURL == nil && retryCount <= maxRetries {
                print("🔄 Stream extraction attempt \(retryCount + 1) for: \(song.title)")
                
                // Method 1: Python helper
                do {
                    let json = try await runHelper(arguments: ["stream_url", song.id])
                    if let error = json["error"] as? String {
                        print("⚠️ Python extraction failed: \(error)")
                        errorMsg = error
                    } else if let urlString = json["stream_url"] as? String, let url = URL(string: urlString) {
                        streamURL = url
                        print("✅ Python extraction succeeded")
                        break
                    }
                } catch {
                    print("⚠️ Python helper failed: \(error)")
                    errorMsg = error.localizedDescription
                }
                
                // Method 2: Web fallback if Python failed
                if streamURL == nil {
                    print("🌐 Trying web extraction...")
                    if let webURL = await self.extractStreamURLFromWeb(videoId: song.id) {
                        streamURL = URL(string: webURL)
                        print("✅ Web extraction succeeded")
                        break
                    }
                }
                
                retryCount += 1
                if streamURL == nil && retryCount <= maxRetries {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                }
            }
            
            // Handle final result - simple error handling
            guard let url = streamURL else {
                await MainActor.run { 
                    let errorMsg = errorMsg ?? "Could not extract stream URL after \(retryCount + 1) attempts"
                    self.errorMessage = errorMsg
                    print("❌ Stream extraction failed for '\(song.title)': \(errorMsg)")
                    MPNowPlayingInfoCenter.default().playbackState = .stopped
                }
                return
            }
            
            // Create new player and start playback
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            self.player = player
            player.play()
            self.didTriggerEndForCurrentItem = false
            
            print("🎵 Setting up player observer for new song: \(song.title)")

            // CRITICAL FIX: Remove old observer before setting up new one
            if let oldToken = self.endObserverToken {
                print("🧹 Removing old AVPlayerItemDidPlayToEndTime observer")
                NotificationCenter.default.removeObserver(oldToken)
                self.endObserverToken = nil
            }

            await self.configureNowPlaying(for: song, streamURL: url)
            self.observePlaybackProgress()
            self.configureRemoteCommandCenter()
            self.endObserverToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                print("🔥🔥🔥 AVPlayerItemDidPlayToEndTime TRIGGERED! 🔥🔥🔥")
                guard let self else { 
                    print("⚠️ Self is nil in AVPlayerItemDidPlayToEndTime observer")
                    return 
                }
                print("🔥 Song ended via AVPlayer notification - flag: \(self.didTriggerEndForCurrentItem)")
                Task { @MainActor in
                    if !self.didTriggerEndForCurrentItem {
                        self.didTriggerEndForCurrentItem = true
                        print("🔥 Triggering handleSongEnded()")
                        // Add a small delay to ensure the player state is properly updated
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                        self.handleSongEnded()
                    } else {
                        print("⚠️ didTriggerEndForCurrentItem is already true - skipping")
                    }
                }
            }
            
            // BACKUP: Monitor playback time to detect end (fallback if notification fails)
            Task {
                await MainActor.run {
                    self.monitorPlaybackEnd(for: item)
                }
            }
        }
    }
    
    private func handleSongEnded() {
        print("🎭 === SIMPLE SONG ENDED HANDLER ===")
        print("🎵 Current song: \(nowPlaying?.title ?? "None")")
        
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        
        // Get current song
        guard let currentSong = nowPlaying else {
            print("❌ No current song to auto-play from")
            return
        }
        
        print("⚙️ Auto-play setting: \(SettingsManager.shared.autoPlayNext)")
        
        // Check if auto-play is enabled
        guard SettingsManager.shared.autoPlayNext else { 
            print("❌ Auto-play is disabled in settings")
            return 
        }
        
        // Simple next song finding - try each context in order
        if let nextSong = findNextSongSimple(for: currentSong) {
            print("✅ Playing next song: \(nextSong.title)")
            // Use a simple play call without complex context management
            Task {
                await MainActor.run {
                    self.play(song: nextSong)
                }
            }
        } else {
            print("❌ No next song found")
        }
        
        print("🎭 === END SIMPLE SONG ENDED ===")
    }
    
    // Simplified next song finder - less complex, more reliable
    private func findNextSongSimple(for currentSong: SongItem) -> SongItem? {
        print("🔍 === SIMPLE NEXT SONG FINDER ===")
        print("🎵 Looking for next after: \(currentSong.title)")
        
        // Priority 1: Album songs (most common use case)
        if !albumSongs.isEmpty {
            if let currentIndex = albumSongs.firstIndex(where: { $0.id == currentSong.id }),
               currentIndex < albumSongs.count - 1 {
                let nextSong = albumSongs[currentIndex + 1]
                print("✅ Found next in album: \(nextSong.title)")
                return nextSong
            }
        }
        
        // Priority 2: Artist songs
        if !artistSongs.isEmpty {
            if let currentIndex = artistSongs.firstIndex(where: { $0.id == currentSong.id }),
               currentIndex < artistSongs.count - 1 {
                let nextSong = artistSongs[currentIndex + 1]
                print("✅ Found next in artist songs: \(nextSong.title)")
                return nextSong
            }
        }
        
        // Priority 3: Search results
        if !songs.isEmpty {
            if let currentIndex = songs.firstIndex(where: { $0.id == currentSong.id }),
               currentIndex < songs.count - 1 {
                let nextSong = songs[currentIndex + 1]
                print("✅ Found next in search results: \(nextSong.title)")
                return nextSong
            }
        }
        
        // Priority 4: Favorites
        if !favoriteSongs.isEmpty {
            if let currentIndex = favoriteSongs.firstIndex(where: { $0.id == currentSong.id }),
               currentIndex < favoriteSongs.count - 1 {
                let nextSong = favoriteSongs[currentIndex + 1]
                print("✅ Found next in favorites: \(nextSong.title)")
                return nextSong
            }
        }
        
        // Priority 5: Videos
        if !videos.isEmpty {
            if let currentIndex = videos.firstIndex(where: { $0.id == currentSong.id }),
               currentIndex < videos.count - 1 {
                let nextVideo = videos[currentIndex + 1]
                let nextSong = SongItem(
                    id: nextVideo.id,
                    title: nextVideo.title,
                    artists: nextVideo.artists,
                    album: nil,
                    duration: nextVideo.duration,
                    thumbnail: nextVideo.thumbnail
                )
                print("✅ Found next in videos: \(nextSong.title)")
                return nextSong
            }
        }
        
        print("❌ No next song found in any context")
        return nil
    }
    
    private func playNextFoundSong(_ nextSong: SongItem, after currentSong: SongItem) {
        print("🎵 === PLAYING NEXT SONG ====")
        print("🎵 From: \(currentSong.title)")
        print("🎵 To: \(nextSong.title)")
        print("🎯 Current context: isPlayingFromPlaylist=\(isPlayingFromPlaylist), currentPlaylistIndex=\(currentPlaylistIndex)")
        
        // Set correct playlist context based on where we found the next song
        if isPlayingFromPlaylist && !currentPlaylist.isEmpty {
            // Use existing playlist context and increment index
            let nextIndex = currentPlaylistIndex + 1
            print("✅ Using existing playlist context: \(currentPlaylist.count) songs, moving to index \(nextIndex)")
            play(song: nextSong, fromPlaylist: currentPlaylist, atIndex: nextIndex)
        } else if albumSongs.contains(where: { $0.id == nextSong.id }),
                  let nextIndex = albumSongs.firstIndex(where: { $0.id == nextSong.id }) {
            // Playing from album
            print("🎧 Setting album context: \(albumSongs.count) songs, index \(nextIndex)")
            play(song: nextSong, fromPlaylist: albumSongs, atIndex: nextIndex)
        } else if artistSongs.contains(where: { $0.id == nextSong.id }),
                  let nextIndex = artistSongs.firstIndex(where: { $0.id == nextSong.id }) {
            // Playing from artist
            print("🎤 Setting artist context: \(artistSongs.count) songs, index \(nextIndex)")
            play(song: nextSong, fromPlaylist: artistSongs, atIndex: nextIndex)
        } else if songs.contains(where: { $0.id == nextSong.id }),
                  let nextIndex = songs.firstIndex(where: { $0.id == nextSong.id }) {
            // Playing from search results
            print("🔍 Setting search results context: \(songs.count) songs, index \(nextIndex)")
            play(song: nextSong, fromPlaylist: songs, atIndex: nextIndex)
        } else if favoriteSongs.contains(where: { $0.id == nextSong.id }),
                  let nextIndex = favoriteSongs.firstIndex(where: { $0.id == nextSong.id }) {
            // Playing from favorites
            print("❤️ Setting favorites context: \(favoriteSongs.count) songs, index \(nextIndex)")
            play(song: nextSong, fromPlaylist: favoriteSongs, atIndex: nextIndex)
        } else if videos.contains(where: { $0.id == nextSong.id }),
                  let nextIndex = videos.firstIndex(where: { $0.id == nextSong.id }) {
            // Playing from videos
            let videoPlaylist = videos.map { SongItem(id: $0.id, title: $0.title, artists: $0.artists, album: nil, duration: $0.duration, thumbnail: $0.thumbnail) }
            print("📺 Setting videos context: \(videoPlaylist.count) songs, index \(nextIndex)")
            play(song: nextSong, fromPlaylist: videoPlaylist, atIndex: nextIndex)
        } else {
            // Fallback: play without specific playlist context but preserve some context
            print("⚠️ No specific context found, playing with minimal context")
            // Try to maintain some basic playlist context for continued auto-play
            if !currentPlaylist.isEmpty {
                // Create a simple continuation context
                let continuationPlaylist = [nextSong]
                play(song: nextSong, fromPlaylist: continuationPlaylist, atIndex: 0)
            } else {
                play(song: nextSong)
            }
        }
        
        print("🎵 === END PLAYING NEXT SONG ====")
    }
    
    // MARK: - Manual Controls (Next/Previous)
    
    // Simplified backup monitoring for song end detection
    private func monitorPlaybackEnd(for item: AVPlayerItem) {
        Task {
            // Wait for player to be ready
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            while item.status == .readyToPlay && player?.currentItem == item && !didTriggerEndForCurrentItem {
                let currentTime = item.currentTime().seconds
                let duration = item.duration.seconds
                
                // Simple end detection - trigger at 1 second remaining
                if duration > 0 && currentTime > 0 && (duration - currentTime) < 1.0 {
                    await MainActor.run {
                        if !self.didTriggerEndForCurrentItem {
                            self.didTriggerEndForCurrentItem = true
                            print("🔥 Song ending detected - triggering auto-play")
                            Task {
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                                await MainActor.run {
                                    self.handleSongEnded()
                                }
                            }
                        }
                    }
                    break
                }
                
                // Check every second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
    
    // MARK: - Manual Controls (Next/Previous)
    
    private func playNextTrack() {
        print("🎵 Manual next track requested")
        
        guard let currentSong = nowPlaying else {
            print("❌ No current song for manual next")
            return
        }
        
        if let nextSong = findNextSongSimple(for: currentSong) {
            print("✅ Playing next song: \(nextSong.title)")
            playNextFoundSong(nextSong, after: currentSong)
        } else {
            print("❌ No next song available for manual next")
        }
    }
    
    private func playPreviousTrack() {
        print("🎵 Manual previous track requested")
        
        guard let currentSong = nowPlaying else {
            print("❌ No current song for manual previous")
            return
        }
        
        if let previousSong = findPreviousSong(for: currentSong) {
            print("✅ Playing previous song: \(previousSong.title)")
            playPreviousFoundSong(previousSong, before: currentSong)
        } else {
            print("❌ No previous song available")
        }
    }
    
    private func findPreviousSong(for currentSong: SongItem) -> SongItem? {
        print("🔍 Searching for previous song before: \(currentSong.title)")
        
        // Method 1: Check if we have explicit playlist context
        if isPlayingFromPlaylist && !currentPlaylist.isEmpty && 
           currentPlaylistIndex > 0 {
            let previousSong = currentPlaylist[currentPlaylistIndex - 1]
            print("✅ Found previous in saved playlist: \(previousSong.title) at index \(currentPlaylistIndex - 1)")
            return previousSong
        }
        
        // Method 2: Album songs - highest priority
        if !albumSongs.isEmpty,
           let currentIndex = albumSongs.firstIndex(where: { $0.id == currentSong.id }),
           currentIndex > 0 {
            let previousSong = albumSongs[currentIndex - 1]
            print("✅ Found previous in album: \(previousSong.title)")
            return previousSong
        }
        
        // Method 3: Artist songs
        if !artistSongs.isEmpty,
           let currentIndex = artistSongs.firstIndex(where: { $0.id == currentSong.id }),
           currentIndex > 0 {
            let previousSong = artistSongs[currentIndex - 1]
            print("✅ Found previous in artist songs: \(previousSong.title)")
            return previousSong
        }
        
        // Method 4: Search results
        if !songs.isEmpty,
           let currentIndex = songs.firstIndex(where: { $0.id == currentSong.id }),
           currentIndex > 0 {
            let previousSong = songs[currentIndex - 1]
            print("✅ Found previous in search results: \(previousSong.title)")
            return previousSong
        }
        
        // Method 5: Videos
        if !videos.isEmpty,
           let currentIndex = videos.firstIndex(where: { $0.id == currentSong.id }),
           currentIndex > 0 {
            let previousVideo = videos[currentIndex - 1]
            let previousSong = SongItem(
                id: previousVideo.id,
                title: previousVideo.title,
                artists: previousVideo.artists,
                album: nil,
                duration: previousVideo.duration,
                thumbnail: previousVideo.thumbnail
            )
            print("✅ Found previous in videos: \(previousSong.title)")
            return previousSong
        }
        
        // Method 6: Favorites
        if !favoriteSongs.isEmpty,
           let currentIndex = favoriteSongs.firstIndex(where: { $0.id == currentSong.id }),
           currentIndex > 0 {
            let previousSong = favoriteSongs[currentIndex - 1]
            print("✅ Found previous in favorites: \(previousSong.title)")
            return previousSong
        }
        
        print("❌ No previous song found in any category")
        return nil
    }
    
    private func playPreviousFoundSong(_ previousSong: SongItem, before currentSong: SongItem) {
        print("🎵 Playing previous song: \(previousSong.title)")
        
        // Set correct playlist context based on where we found the previous song
        if isPlayingFromPlaylist && !currentPlaylist.isEmpty {
            // Use existing playlist context
            play(song: previousSong, fromPlaylist: currentPlaylist, atIndex: currentPlaylistIndex - 1)
        } else if albumSongs.contains(where: { $0.id == previousSong.id }),
                  let previousIndex = albumSongs.firstIndex(where: { $0.id == previousSong.id }) {
            // Playing from album
            play(song: previousSong, fromPlaylist: albumSongs, atIndex: previousIndex)
        } else if artistSongs.contains(where: { $0.id == previousSong.id }),
                  let previousIndex = artistSongs.firstIndex(where: { $0.id == previousSong.id }) {
            // Playing from artist
            play(song: previousSong, fromPlaylist: artistSongs, atIndex: previousIndex)
        } else if songs.contains(where: { $0.id == previousSong.id }),
                  let previousIndex = songs.firstIndex(where: { $0.id == previousSong.id }) {
            // Playing from search results
            play(song: previousSong, fromPlaylist: songs, atIndex: previousIndex)
        } else if favoriteSongs.contains(where: { $0.id == previousSong.id }),
                  let previousIndex = favoriteSongs.firstIndex(where: { $0.id == previousSong.id }) {
            // Playing from favorites
            play(song: previousSong, fromPlaylist: favoriteSongs, atIndex: previousIndex)
        } else if videos.contains(where: { $0.id == previousSong.id }),
                  let previousIndex = videos.firstIndex(where: { $0.id == previousSong.id }) {
            // Playing from videos
            let videoPlaylist = videos.map { SongItem(id: $0.id, title: $0.title, artists: $0.artists, album: nil, duration: $0.duration, thumbnail: $0.thumbnail) }
            play(song: previousSong, fromPlaylist: videoPlaylist, atIndex: previousIndex)
        } else {
            // Fallback: play without specific playlist context
            play(song: previousSong)
        }
    }
    
    // Try to find a logical previous song when not in an explicit playlist
    private func tryAutoPlayPreviousFromAvailableSongs() {
        guard let currentSong = nowPlaying else { return }
        
        // Check if we can go back in album songs
        if !albumSongs.isEmpty, let currentIndex = albumSongs.firstIndex(where: { $0.id == currentSong.id }),
           currentIndex > 0 {
            let previousSong = albumSongs[currentIndex - 1]
            print("Playing previous from album: \(previousSong.title)")
            play(song: previousSong, fromPlaylist: albumSongs, atIndex: currentIndex - 1)
            return
        }
        
        // Check if we can go back in artist songs
        if !artistSongs.isEmpty, let currentIndex = artistSongs.firstIndex(where: { $0.id == currentSong.id }),
           currentIndex > 0 {
            let previousSong = artistSongs[currentIndex - 1]
            print("Playing previous from artist songs: \(previousSong.title)")
            play(song: previousSong, fromPlaylist: artistSongs, atIndex: currentIndex - 1)
            return
        }
        
        // Check if we can go back in search results
        if !songs.isEmpty, let currentIndex = songs.firstIndex(where: { $0.id == currentSong.id }),
           currentIndex > 0 {
            let previousSong = songs[currentIndex - 1]
            print("Playing previous from search results: \(previousSong.title)")
            play(song: previousSong, fromPlaylist: songs, atIndex: currentIndex - 1)
            return
        }
        
        // Check if we can go back in favorites
        if !favoriteSongs.isEmpty, let currentIndex = favoriteSongs.firstIndex(where: { $0.id == currentSong.id }),
           currentIndex > 0 {
            let previousSong = favoriteSongs[currentIndex - 1]
            print("Playing previous from favorites: \(previousSong.title)")
            play(song: previousSong, fromPlaylist: favoriteSongs, atIndex: currentIndex - 1)
            return
        }
        
        print("No logical previous song found")
    }

    private var lastProgressUpdate: TimeInterval = 0
    private var lastPlaybackRate: Float = 0
    
    private func observePlaybackProgress() {
        guard let player = player else { return }
        // Use more frequent updates for reliable end-of-song detection
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] currentTime in
            guard let self else { return }

            let currentSeconds = CMTimeGetSeconds(currentTime)
            let rate = player.rate

            Task { @MainActor in
                // Update Now Playing info less frequently to save energy
                let timeDiff = abs(currentSeconds - self.lastProgressUpdate)
                let rateDiff = abs(rate - self.lastPlaybackRate)
                let shouldUpdateNowPlaying = timeDiff > 5.0 || rateDiff > 0.1

                if shouldUpdateNowPlaying {
                    self.lastProgressUpdate = currentSeconds
                    self.lastPlaybackRate = rate

                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    // If duration wasn't known at start (e.g., artist page items), try to fill from the player item once available
                    if info[MPMediaItemPropertyPlaybackDuration] == nil || (info[MPMediaItemPropertyPlaybackDuration] as? Double ?? 0) <= 0 {
                        if let durationTime = self.player?.currentItem?.duration {
                            let total = CMTimeGetSeconds(durationTime)
                            if total.isFinite && total > 0 {
                                info[MPMediaItemPropertyPlaybackDuration] = total
                            }
                        }
                    }
                    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentSeconds
                    info[MPNowPlayingInfoPropertyPlaybackRate] = rate
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                    MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
                }

                // Check for end-of-song with auto-play enabled (improved reliability)  
                if SettingsManager.shared.autoPlayNext,
                   let durationTime = self.player?.currentItem?.duration,
                   durationTime.isNumeric && !durationTime.isIndefinite,
                   CMTimeGetSeconds(durationTime).isFinite {
                    let total = CMTimeGetSeconds(durationTime)
                    // Trigger auto-play when less than 0.5 seconds remaining (more aggressive)
                    if total > 0 && total - currentSeconds <= 0.5 && !self.didTriggerEndForCurrentItem {
                        print("🔥 Song ending detected via progress monitoring - total: \(total), current: \(currentSeconds), remaining: \(total - currentSeconds)")
                        self.didTriggerEndForCurrentItem = true
                        
                        // Add small delay to ensure smooth transition
                        Task {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                            await MainActor.run {
                                self.handleSongEnded()
                            }
                        }
                    }
                }
            }
        }
    }

    private func configureNowPlaying(for song: SongItem, streamURL: URL) async {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = song.title
        if let artists = song.artists { info[MPMediaItemPropertyArtist] = artists }
        if let album = song.album { info[MPMediaItemPropertyAlbumTitle] = album }

        if let durationString = song.duration, let seconds = Self.parseDurationToSeconds(durationString) {
            info[MPMediaItemPropertyPlaybackDuration] = seconds
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0

        if let thumb = song.thumbnail, let url = URL(string: thumb) {
            do {
                // Use energy-efficient URLSession configuration
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0 // Shorter timeout to save energy
                request.cachePolicy = .returnCacheDataElseLoad // Use cache when possible
                
                let (data, _) = try await URLSession.shared.data(for: request)
                
                // Limit image size to save memory and energy
                guard data.count < 1_000_000 else { return } // Skip images > 1MB
                
                if let image = NSImage(data: data) {
                    // Resize large images to save memory
                    let maxSize: CGFloat = 300
                    let resizedImage = if image.size.width > maxSize || image.size.height > maxSize {
                        image.resized(to: NSSize(width: min(image.size.width, maxSize), 
                                               height: min(image.size.height, maxSize)))
                    } else {
                        image
                    }
                    
                    let artwork = MPMediaItemArtwork(boundsSize: resizedImage.size) { _ in resizedImage }
                    info[MPMediaItemPropertyArtwork] = artwork
                }
            } catch {
                // Ignore artwork errors to save energy
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    private static func parseDurationToSeconds(_ text: String) -> Double? {
        // Supports "mm:ss" or "hh:mm:ss"
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        return nil
    }

    private func configureRemoteCommandCenter() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self, let player = self.player else { return .noActionableNowPlayingItem }
            player.play()
            MPNowPlayingInfoCenter.default().playbackState = .playing
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, let player = self.player else { return .noActionableNowPlayingItem }
            player.pause()
            MPNowPlayingInfoCenter.default().playbackState = .paused
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let player = self.player else { return .noActionableNowPlayingItem }
            if player.rate > 0 {
                player.pause()
                MPNowPlayingInfoCenter.default().playbackState = .paused
            } else {
                player.play()
                MPNowPlayingInfoCenter.default().playbackState = .playing
            }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let player = self.player, let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = CMTime(seconds: posEvent.positionTime, preferredTimescale: 600)
            player.seek(to: time)
            return .success
        }
        
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            self.playNextTrack()
            return .success
        }
        
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            self.playPreviousTrack()
            return .success
        }
    }
    
    func showAlbumDetails(_ album: AlbumItem) async {
        selectedAlbum = album
        selectedArtist = nil
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        
        do {
            let resp = try await runHelper(arguments: ["album_songs", album.id])
            if let error = resp["error"] as? String {
                self.errorMessage = "Album error: \(error)"
                self.albumSongs = []
                return
            }
            if let songsData = resp["songs"] as? [[String: Any]] {
                let jsonData = try JSONSerialization.data(withJSONObject: songsData)
                let songs = try JSONDecoder().decode([SongItem].self, from: jsonData)
                self.albumSongs = songs
                // Update playlist context if current song might be in new album
                self.updatePlaylistContextIfNeeded()
                if songs.isEmpty {
                    self.errorMessage = "No songs found in this album"
                }
            } else {
                self.errorMessage = "Invalid response format for album songs"
                self.albumSongs = []
            }
        } catch {
            self.errorMessage = "Failed to load album: \(error.localizedDescription)"
            self.albumSongs = []
        }
    }
    
    func showArtistDetails(_ artist: ArtistItem) async {
        selectedArtist = artist
        selectedAlbum = nil
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        
        do {
            let resp = try await runHelper(arguments: ["artist_content", artist.id])
            
            if let error = resp["error"] as? String {
                self.errorMessage = error
                self.artistSongs = []
                self.artistAlbums = []
                return
            }
            
            if let songsData = resp["songs"] as? [[String: Any]] {
                let jsonData = try JSONSerialization.data(withJSONObject: songsData)
                let songs = try JSONDecoder().decode([SongItem].self, from: jsonData)
                self.artistSongs = songs
            } else {
                self.artistSongs = []
            }
            
            if let albumsData = resp["albums"] as? [[String: Any]] {
                let jsonData = try JSONSerialization.data(withJSONObject: albumsData)
                let albums = try JSONDecoder().decode([AlbumItem].self, from: jsonData)
                self.artistAlbums = albums
            } else {
                self.artistAlbums = []
            }
            
            // Update playlist context if current song might be in new artist songs
            self.updatePlaylistContextIfNeeded()
        } catch {
            self.errorMessage = error.localizedDescription
            self.artistSongs = []
            self.artistAlbums = []
        }
    }
    
    func clearDetails() {
        selectedAlbum = nil
        selectedArtist = nil
        albumSongs = []
        artistSongs = []
        artistAlbums = []
    }

    private func runHelper(arguments: [String]) async throws -> [String: Any] {
        // Make sure environment is ready first (handles first-run installs)
        await ensurePythonSiteInstalled()
        
        guard let pythonExec = selectPythonExec() else {
            return ["error": "Python 3 not found. Please install Python 3 or bundle it with the app."]
        }
        let siteDir = sitePackagesPath()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()

            // Inline Python to avoid bundling external files
            let pythonCode = """
import json, os, sys
from typing import Any, Dict, List, Optional
site = r"\(siteDir)"
if os.path.isdir(site):
    sys.path.insert(0, site)
# Allow importing directly from bundled wheels without pip (pure-Python)
res = os.environ.get("SM_RESOURCES_PATH")
if res:
    wheels = os.path.join(res, "PythonWheels")
    if os.path.isdir(wheels):
        for name in os.listdir(wheels):
            if name.endswith('.whl'):
                sys.path.insert(0, os.path.join(wheels, name))
try:
    from ytmusicapi import YTMusic
except Exception as e:
    print(json.dumps({"error": f"ytmusicapi not available: {e}"}))
    sys.exit(0)

def load_ytmusic() -> Optional[YTMusic]:
    script_dir = os.getcwd()
    local_headers = os.path.join(script_dir, "headers_auth.json")
    app_support_headers = os.path.expanduser("~/Library/Application Support/SpotlightMusic/headers_auth.json")
    try:
        if os.path.exists(local_headers):
            return YTMusic(local_headers)
        if os.path.exists(app_support_headers):
            return YTMusic(app_support_headers)
        return YTMusic()
    except Exception as e:
        print(json.dumps({"error": f"Failed to initialize YTMusic: {e}"}))
        return None

def simplify_song(item: Dict[str, Any]):
    try:
        # For artist songs, there's no resultType, so we check for videoId directly
        vid = item.get("videoId")
        if not vid:
            return None

        # Handle different data structures for search results vs artist songs
        if "resultType" in item and item.get("resultType") != "song":
            return None

        artists = item.get("artists") or []
        thumbs = item.get("thumbnails") or []

        # Handle album data - could be dict or string
        album_name = None
        if "album" in item:
            album_data = item.get("album")
            if isinstance(album_data, dict):
                album_name = album_data.get("name")
            elif isinstance(album_data, str):
                album_name = album_data

        # Normalize duration to mm:ss for consistent UI/seek behavior
        duration_text: Optional[str] = None
        # Common text fields first
        for key in ("duration", "length", "lengthText"):
            val = item.get(key)
            if isinstance(val, str) and val:
                duration_text = val
                break
        # Fallback to second-based fields
        if not duration_text:
            sec_val = item.get("duration_seconds") or item.get("lengthSeconds")
            try:
                if isinstance(sec_val, (int, float)):
                    secs = int(sec_val)
                elif isinstance(sec_val, str) and sec_val.isdigit():
                    secs = int(sec_val)
                else:
                    secs = None
                if secs is not None and secs >= 0:
                    minutes = secs // 60
                    rem = secs % 60
                    duration_text = f"{minutes}:{rem:02d}"
            except Exception:
                duration_text = None

        return {
            "id": vid,
            "videoId": vid,
            "title": item.get("title") or "",
            "artists": ", ".join([a.get("name", "") for a in artists if isinstance(a, dict)]),
            "album": album_name,
            "duration": duration_text,
            "thumbnail": thumbs[-1]["url"] if thumbs else None,
        }
    except Exception:
        return None

def handle_search(q: str):
    ytm = load_ytmusic()
    if ytm is None:
        return
    try:
        res_songs = ytm.search(q, filter="songs") or []
        res_albums = ytm.search(q, filter="albums") or []
        res_artists = ytm.search(q, filter="artists") or []
        res_videos = ytm.search(q, filter="videos") or []

        def simplify_album(it: Dict[str, Any]):
            if it.get("resultType") != "album":
                return None
            browse_id = it.get("browseId")
            if not browse_id:
                return None
            thumbs = it.get("thumbnails") or []
            artist = None
            if isinstance(it.get("artists"), list) and len(it.get("artists")):
                artist = it.get("artists")[0].get("name")
            return {
                "id": browse_id,
                "title": it.get("title") or "",
                "artist": artist,
                "year": it.get("year"),
                "thumbnail": thumbs[-1]["url"] if thumbs else None,
            }

        def simplify_artist(it: Dict[str, Any]):
            if it.get("resultType") != "artist":
                return None
            browse_id = it.get("browseId")
            if not browse_id:
                return None
            thumbs = it.get("thumbnails") or []
            return {
                "id": browse_id,
                "name": it.get("artist") or it.get("title") or "",
                "subscribers": it.get("subscribers"),
                "thumbnail": thumbs[-1]["url"] if thumbs else None,
            }

        def simplify_video(it: Dict[str, Any]):
            if it.get("resultType") != "video":
                return None
            vid = it.get("videoId")
            if not vid:
                return None
            thumbs = it.get("thumbnails") or []
            artists = it.get("artists") or []
            return {
                "id": vid,
                "title": it.get("title") or "",
                "artists": ", ".join([a.get("name", "") for a in artists if isinstance(a, dict)]),
                "duration": it.get("duration") or it.get("length"),
                "thumbnail": thumbs[-1]["url"] if thumbs else None,
                "views": it.get("views"),
            }

        out = {
            "songs": [s for s in (simplify_song(i) for i in res_songs) if s],
            "albums": [a for a in (simplify_album(i) for i in res_albums) if a],
            "artists": [a for a in (simplify_artist(i) for i in res_artists) if a],
            "videos": [v for v in (simplify_video(i) for i in res_videos) if v],
        }
        print(json.dumps(out))
    except Exception as e:
        print(json.dumps({"error": f"Search failed: {e}"}))

def handle_stream_url(video_id: str):
    \"\"\"Extract stream URL with fallback methods for reliability.\"\"\"
    # Try yt-dlp first with multiple format options
    try:
        from yt_dlp import YoutubeDL
        
        # Multiple format strategies
        format_strategies = [
            "bestaudio[ext=m4a]/best[height<=480]/best",
            "bestaudio/best[height<=720]/best", 
            "worst[height<=480]/worst",
            "best/worst"
        ]
        
        url = f"https://www.youtube.com/watch?v={video_id}"
        
        for fmt_strategy in format_strategies:
            try:
                ydl_opts = {
                    "format": fmt_strategy,
                    "quiet": True,
                    "noplaylist": True,
                    "nocheckcertificate": True,
                    "no_warnings": True,
                    "extractaudio": True,
                    "audioformat": "best",
                    # Add more robust options
                    "ignoreerrors": True,
                    "no_check_certificate": True,
                    "geo_bypass": True,
                    "prefer_insecure": True
                }
                
                with YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(url, download=False)
                    
                    # Multiple ways to get stream URL
                    stream_url = None
                    
                    # Method 1: Direct URL
                    if "url" in info and info["url"]:
                        stream_url = info["url"]
                    
                    # Method 2: From formats
                    elif "formats" in info:
                        fmts = info.get("formats", [])
                        
                        # Prefer audio-only formats
                        audio_fmts = [f for f in fmts if f.get("acodec") != "none" and f.get("vcodec") == "none"]
                        if audio_fmts:
                            # Sort by quality
                            audio_fmts.sort(key=lambda f: f.get("abr", 0), reverse=True)
                            stream_url = audio_fmts[0].get("url")
                        
                        # Fallback to any format with audio
                        if not stream_url:
                            audio_any = [f for f in fmts if f.get("acodec") != "none" and f.get("url")]
                            if audio_any:
                                audio_any.sort(key=lambda f: f.get("abr", 0), reverse=True)
                                stream_url = audio_any[0]["url"]
                    
                    if stream_url:
                        print(json.dumps({"stream_url": stream_url}))
                        return
                        
            except Exception as fmt_error:
                # Continue to next format strategy
                continue
                
    except ImportError:
        # yt-dlp not available, try web-based approach
        pass
    except Exception as e:
        # Log the error but try fallback
        pass
    
    # Web-based fallback using YouTube's embed API
    try:
        import urllib.request
        import urllib.parse
        import re
        
        # Try YouTube embed page which often has accessible formats
        embed_url = f"https://www.youtube.com/embed/{video_id}"
        headers = {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        }
        
        request = urllib.request.Request(embed_url, headers=headers)
        with urllib.request.urlopen(request, timeout=10) as response:
            html = response.read().decode('utf-8')
            
            # Extract player config
            player_match = re.search(r'ytInitialPlayerResponse\\s*=\\s*(\\{.+?\\});', html)
            if player_match:
                import json as json_lib
                player_data = json_lib.loads(player_match.group(1))
                
                streaming_data = player_data.get('streamingData', {})
                formats = streaming_data.get('formats', []) + streaming_data.get('adaptiveFormats', [])
                
                # Find audio format
                for fmt in formats:
                    if fmt.get('mimeType', '').startswith('audio/') and fmt.get('url'):
                        print(json_lib.dumps({"stream_url": fmt['url']}))
                        return
    
    except Exception as web_error:
        pass
    
    # Final fallback: Use YouTube Music direct if available
    try:
        ytm = load_ytmusic()
        if ytm:
            # Try to get song info and use that
            song_info = ytm.get_song(video_id)
            if song_info and 'streamingData' in song_info:
                formats = song_info['streamingData'].get('adaptiveFormats', [])
                for fmt in formats:
                    if fmt.get('mimeType', '').startswith('audio/') and fmt.get('url'):
                        print(json.dumps({"stream_url": fmt['url']}))
                        return
    except:
        pass
    
    print(json.dumps({"error": f"Could not extract stream URL for video {video_id}. All methods failed."}))

def handle_album_songs(album_id: str):
    ytm = load_ytmusic()
    if ytm is None:
        return
    try:
        album_data = ytm.get_album(album_id)
        
        # Debug: Check what we got
        if not album_data:
            print(json.dumps({"error": "No album data returned"}))
            return
            
        tracks = album_data.get("tracks") or []
        if not tracks:
            print(json.dumps({"error": f"No tracks found in album. Keys available: {list(album_data.keys())}"}))
            return
        
        songs = []
        
        for i, track in enumerate(tracks):
            try:
                # Album tracks have a different structure than search results
                vid = track.get("videoId")
                if not vid:
                    # Try alternative keys
                    vid = track.get("id") or track.get("playlistId")
                    if not vid:
                        continue
                    
                title = track.get("title") or ""
                artists = track.get("artists") or []
                artist_names = ", ".join([a.get("name", "") for a in artists if isinstance(a, dict)])
                
                # Get duration - try multiple possible keys
                duration = None
                if "duration" in track and track["duration"]:
                    duration = track["duration"]
                elif "duration_seconds" in track and track["duration_seconds"]:
                    # Convert seconds to mm:ss format
                    seconds = int(track["duration_seconds"])
                    minutes = seconds // 60
                    secs = seconds % 60
                    duration = f"{minutes}:{secs:02d}"
                elif "lengthText" in track:
                    duration = track["lengthText"]
                
                # Get thumbnail from album data if not in track
                thumbnail = None
                if "thumbnails" in track and track["thumbnails"]:
                    thumbnail = track["thumbnails"][-1]["url"]
                elif "thumbnails" in album_data and album_data["thumbnails"]:
                    thumbnail = album_data["thumbnails"][-1]["url"]
                
                # Get album name
                album_name = album_data.get("title") or ""
                
                song = {
                    "id": vid,
                    "videoId": vid,
                    "title": title,
                    "artists": artist_names if artist_names else None,
                    "album": album_name if album_name else None,
                    "duration": duration,
                    "thumbnail": thumbnail,
                }
                songs.append(song)
            except Exception as track_error:
                # Skip problematic tracks but continue processing
                continue
        
        if not songs:
            print(json.dumps({"error": f"No valid songs found. Processed {len(tracks)} tracks."}))
        else:
            print(json.dumps({"songs": songs}))
            
    except Exception as e:
        print(json.dumps({"error": f"Failed to get album songs: {e}"}))

def handle_artist_content(artist_id: str):
    ytm = load_ytmusic()
    if ytm is None:
        print(json.dumps({"error": "Failed to load YTMusic"}))
        return
    try:
        artist_data = ytm.get_artist(artist_id)
        
        # Get top songs
        songs = []
        if "songs" in artist_data and "results" in artist_data["songs"]:
            for track in artist_data["songs"]["results"][:10]:  # Limit to top 10 songs
                song = simplify_song(track)
                if song:
                    songs.append(song)
        
        # Get albums
        albums = []
        if "albums" in artist_data and "results" in artist_data["albums"]:
            for album_data in artist_data["albums"]["results"][:8]:  # Limit to 8 albums
                # For artist albums, resultType might not be present or might be different
                browse_id = album_data.get("browseId")
                if browse_id:
                    thumbs = album_data.get("thumbnails") or []
                    albums.append({
                        "id": browse_id,
                        "title": album_data.get("title") or "",
                        "artist": artist_data.get("name") or "",
                        "year": album_data.get("year"),
                        "thumbnail": thumbs[-1]["url"] if thumbs else None,
                    })
        
        print(json.dumps({"songs": songs, "albums": albums}))
    except Exception as e:
        print(json.dumps({"error": f"Failed to get artist content: {e}"}))

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No command"}))
        return
    cmd = sys.argv[1]
    if cmd == "search_all":
        q = " ".join(sys.argv[2:]).strip()
        handle_search(q)
    elif cmd == "stream_url":
        vid = sys.argv[2] if len(sys.argv) > 2 else ""
        handle_stream_url(vid)
    elif cmd == "album_songs":
        album_id = sys.argv[2] if len(sys.argv) > 2 else ""
        handle_album_songs(album_id)
    elif cmd == "artist_content":
        artist_id = sys.argv[2] if len(sys.argv) > 2 else ""
        handle_artist_content(artist_id)
    else:
        print(json.dumps({"error": f"Unknown command: {cmd}"}))

main()
"""

            process.executableURL = URL(fileURLWithPath: pythonExec)
            process.arguments = ["-c", pythonCode] + arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            var env = ProcessInfo.processInfo.environment
            env["PYTHONPATH"] = [siteDir, env["PYTHONPATH"]].compactMap { $0 }.joined(separator: ":")
            if let resPath = Bundle.main.resourceURL?.path { env["SM_RESOURCES_PATH"] = resPath }
            process.environment = env

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.terminationHandler = { _ in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                if data.isEmpty {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(returning: ["error": errStr])
                    return
                }
                do {
                    if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        continuation.resume(returning: obj)
                    } else {
                        continuation.resume(throwing: NSError(domain: "Parsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected output"]))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    deinit {
        // Clean up observer when ViewModel is deallocated
        if let token = endObserverToken {
            print("🧹 ViewModel deinit: removing AVPlayerItemDidPlayToEndTime observer")
            NotificationCenter.default.removeObserver(token)
        }
    }
}


