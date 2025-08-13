# Spotlight Music

A modern macOS music player app built with SwiftUI that integrates with YouTube Music for streaming audio content.

## Features

### 🎵 Content Discovery
- **Search**: Find songs, albums, artists, and videos
- **Browse**: Explore album details and artist catalogs
- **Favorites**: Save and manage your favorite tracks

### 🎧 Playback
- **Audio Streaming**: High-quality audio playback from YouTube Music
- **Media Controls**: Full integration with macOS media controls (menu bar, Control Center)
- **Auto-play**: Seamless track progression within playlists
- **Instant Switching**: Immediate song switching with no overlap

### 🎛️ Navigation
- **Previous/Next**: Navigate through playlists with media keys
- **Album View**: Browse complete album tracklists
- **Artist View**: Explore artist discographies and top songs
- **Video Support**: Play music videos as audio tracks

### ⚡ Performance Optimizations
- **Energy Efficient**: Optimized for low energy impact and battery life
- **Low CPU Usage**: Minimal system resource consumption
- **Smart Caching**: Intelligent search result caching
- **Background Processing**: Non-blocking UI with background operations

## Requirements

- macOS 13.0 or later
- Python 3.7+ (for YouTube Music integration)
- Internet connection for streaming

## Installation

### Prerequisites
1. Install Python 3:
   ```bash
   # Using Homebrew
   brew install python3
   
   # Or download from python.org
   ```

2. The app will automatically install required Python dependencies (`ytmusicapi` and `yt-dlp`) on first run.

### Building from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/ShubhamPP04/Spotlight-Music.git
   cd Spotlight-Music
   ```

2. Open `Spotlight Music.xcodeproj` in Xcode

3. Build and run the project (⌘+R)

### Install from DMG
1. Download the latest `.dmg` from the Releases page or build one via `PackagingResources/package.sh`.
2. Open the DMG and drag `Spotlight Music.app` into the `Applications` folder.
3. If macOS blocks the app due to quarantine, remove the quarantine attribute:

```bash
xattr -rd com.apple.quarantine "/Applications/Spotlight Music.app"
```

## Usage

### Basic Search
1. Launch the app
2. Type in the search bar to find music content
3. Click on any item to play it immediately

### Media Controls
- Use macOS media keys for play/pause/next/previous
- Control playback from the menu bar or Control Center
- Click anywhere on a song/video row to play it

### Favorites
- Click the heart icon on any song to add it to favorites
- Access favorites from the home screen when no search is active

### Album & Artist Exploration
- Click on any album to view its complete tracklist
- Click on any artist to see their top songs and albums
- Use the back button or ESC key to return to search results

## Architecture

### Core Components
- **SwiftUI Interface**: Modern, responsive user interface
- **AVFoundation**: Audio playback engine
- **MediaPlayer Framework**: macOS media controls integration
- **Python Backend**: YouTube Music API integration via `ytmusicapi`

### Performance Features
- **Search Debouncing**: Reduces API calls (800ms delay)
- **Result Caching**: Stores up to 20 recent searches
- **Efficient Animations**: Optimized hover effects (80ms duration)
- **Background Processing**: Progress updates every 10 seconds
- **Image Optimization**: Automatic resizing and size limits
- **Network Throttling**: Maximum 2 concurrent requests

## Configuration

### Python Dependencies
The app automatically manages Python dependencies, but you can manually install them:

```bash
pip3 install ytmusicapi yt-dlp
```

### Authentication (Optional)
For enhanced features, you can provide YouTube Music authentication:

1. Create `headers_auth.json` in the app's Application Support directory:
   ```
   ~/Library/Application Support/SpotlightMusic/headers_auth.json
   ```

2. Follow the [ytmusicapi authentication guide](https://ytmusicapi.readthedocs.io/en/stable/setup.html) to generate the file.

## Development

### Project Structure
```
Spotlight Music/
├── Models.swift          # Data models (Song, Album, Artist, Video)
├── ViewModel.swift       # Business logic and state management
├── ContentView.swift     # Main UI components
├── SettingsManager.swift # App preferences
├── WindowConfigurator.swift # Window management
└── ytmusic_helper.py     # Python backend integration
```

### Key Features Implementation
- **Energy Optimization**: Reduced update frequencies and smart caching
- **Instant Playback**: Immediate UI updates with background loading
- **Media Integration**: Full macOS media controls support
- **Search Caching**: LRU cache for search results
- **Error Handling**: Graceful fallbacks for network issues

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [ytmusicapi](https://github.com/sigma67/ytmusicapi) - YouTube Music API integration
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) - Video/audio extraction
- YouTube Music - Content source

## Disclaimer

This app is for educational purposes only. It uses publicly available APIs and does not store or redistribute copyrighted content. Users are responsible for complying with YouTube's Terms of Service and applicable copyright laws.