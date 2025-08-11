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
    private var remoteCommandsConfigured = false

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
        if await modulesReady() { return }

        // Try to ensure pip exists
        _ = try? await runProcess(exec: python, args: ["-m", "ensurepip", "--upgrade"]) 

        // Prefer offline wheels from bundle
        if let wheelsDir = Bundle.main.resourceURL?.appendingPathComponent("PythonWheels").path,
           fm.fileExists(atPath: wheelsDir) {
            _ = try? await runProcess(exec: python, args: ["-m", "pip", "install", "--no-index", "--find-links", wheelsDir, "--target", siteDir, "ytmusicapi", "yt-dlp"]) 
        } else {
            _ = try? await runProcess(exec: python, args: ["-m", "pip", "install", "--target", siteDir, "ytmusicapi", "yt-dlp"]) 
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
        } else {
            favoriteSongs.insert(song, at: 0)
        }
        saveFavorites()
    }
    func isFavorite(_ song: SongItem) -> Bool { favoriteSongs.contains(where: { $0.id == song.id }) }
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

    func performSearch(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.songs = []
            self.albums = []
            self.artists = []
            self.videos = []
            return
        }
        
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
    
    func play(song: SongItem, fromPlaylist playlist: [SongItem]?, atIndex index: Int) {
        // Stop current playback immediately
        player?.pause()
        
        // Update UI state immediately for instant feedback
        nowPlaying = song
        
        // Update playlist context
        if let playlist = playlist {
            currentPlaylist = playlist
            currentPlaylistIndex = index
            isPlayingFromPlaylist = true
        } else {
            // Check if this song is in the current album songs
            if let albumIndex = albumSongs.firstIndex(where: { $0.id == song.id }) {
                currentPlaylist = albumSongs
                currentPlaylistIndex = albumIndex
                isPlayingFromPlaylist = true
            } else if let artistIndex = artistSongs.firstIndex(where: { $0.id == song.id }) {
                currentPlaylist = artistSongs
                currentPlaylistIndex = artistIndex
                isPlayingFromPlaylist = true
            } else {
                isPlayingFromPlaylist = false
                currentPlaylist = []
                currentPlaylistIndex = -1
            }
        }
        
        // Clean up previous observers immediately
        if let token = timeObserverToken, let existing = player {
            existing.removeTimeObserver(token)
            timeObserverToken = nil
        }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
        
        // Set loading state in now playing
        MPNowPlayingInfoCenter.default().playbackState = .interrupted
        
        Task {
            do {
                let json = try await runHelper(arguments: ["stream_url", song.id])
                if let error = json["error"] as? String {
                    await MainActor.run { 
                        self.errorMessage = error
                        MPNowPlayingInfoCenter.default().playbackState = .stopped
                    }
                    return
                }
                guard let urlString = json["stream_url"] as? String, let url = URL(string: urlString) else {
                    await MainActor.run { 
                        self.errorMessage = "Invalid stream URL"
                        MPNowPlayingInfoCenter.default().playbackState = .stopped
                    }
                    return
                }
                
                // Create new player and start playback
                let item = AVPlayerItem(url: url)
                let player = AVPlayer(playerItem: item)
                self.player = player
                player.play()

                await self.configureNowPlaying(for: song, streamURL: url)
                self.observePlaybackProgress()
                self.configureRemoteCommandCenter()
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.handleSongEnded()
                    }
                }
            } catch {
                await MainActor.run { 
                    self.errorMessage = error.localizedDescription
                    MPNowPlayingInfoCenter.default().playbackState = .stopped
                }
            }
        }
    }
    
    private func handleSongEnded() {
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        
        // Respect user setting for auto-play next
        if !SettingsManager.shared.autoPlayNext { return }

        // Auto-play next song if playing from a playlist
        if isPlayingFromPlaylist && currentPlaylistIndex >= 0 && currentPlaylistIndex < currentPlaylist.count - 1 {
            let nextIndex = currentPlaylistIndex + 1
            let nextSong = currentPlaylist[nextIndex]
            play(song: nextSong, fromPlaylist: currentPlaylist, atIndex: nextIndex)
        }
    }
    
    private func playNextTrack() {
        guard isPlayingFromPlaylist && currentPlaylistIndex >= 0 && currentPlaylistIndex < currentPlaylist.count - 1 else {
            return
        }
        let nextIndex = currentPlaylistIndex + 1
        let nextSong = currentPlaylist[nextIndex]
        play(song: nextSong, fromPlaylist: currentPlaylist, atIndex: nextIndex)
    }
    
    private func playPreviousTrack() {
        guard isPlayingFromPlaylist && currentPlaylistIndex > 0 else {
            return
        }
        let previousIndex = currentPlaylistIndex - 1
        let previousSong = currentPlaylist[previousIndex]
        play(song: previousSong, fromPlaylist: currentPlaylist, atIndex: previousIndex)
    }

    private var lastProgressUpdate: TimeInterval = 0
    private var lastPlaybackRate: Float = 0
    
    private func observePlaybackProgress() {
        guard let player = player else { return }
        // Reduce update frequency to every 10 seconds to save energy
        let interval = CMTime(seconds: 10, preferredTimescale: 1)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] currentTime in
            guard let self else { return }

            let currentSeconds = CMTimeGetSeconds(currentTime)
            let rate = player.rate

            Task { @MainActor in
                // Only update if there's a significant change (save energy)
                let timeDiff = abs(currentSeconds - self.lastProgressUpdate)
                let rateDiff = abs(rate - self.lastPlaybackRate)
                guard timeDiff > 5.0 || rateDiff > 0.1 else { return }

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
    try:
        from yt_dlp import YoutubeDL
    except Exception as e:
        print(json.dumps({"error": f"yt-dlp not available: {e}"}))
        return
    ydl_opts = {"format": "bestaudio[ext=m4a]/bestaudio/best", "quiet": True, "noplaylist": True, "nocheckcertificate": True}
    url = f"https://www.youtube.com/watch?v={video_id}"
    try:
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            su = info.get("url")
            if not su:
                fmts = info.get("formats") or []
                af = [f for f in fmts if f.get("acodec") and f.get("vcodec") == "none"]
                af.sort(key=lambda f: f.get("abr") or 0, reverse=True)
                su = af[0]["url"] if af else None
            if not su:
                print(json.dumps({"error": "No stream URL found"}))
                return
            print(json.dumps({"stream_url": su}))
    except Exception as e:
        print(json.dumps({"error": f"Extraction failed: {e}"}))

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
}


