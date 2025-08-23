# YouTube Extraction Fix Summary

## Problem
The Spotlight Music app was failing to extract audio from YouTube videos with the error:
```
ERROR: [youtube] 62yox0F5lcA: Requested format is not available. Use --list-formats for a list of available formats.
```

## Root Cause
- YouTube frequently changes their video formats and availability
- The original yt-dlp extraction was using limited format options
- No fallback mechanisms were in place when the primary extraction failed

## Solution Implemented

### 1. Enhanced Python Helper (`ytmusic_helper.py`)
- **Multiple Format Strategies**: Implemented multiple format strings with fallbacks:
  - `bestaudio[ext=m4a]/best[height<=480]/best`
  - `bestaudio/best[height<=720]/best`  
  - `worst[height<=480]/worst`
  - `best/worst`

- **Robust yt-dlp Options**: Added more robust extraction options:
  - `ignoreerrors: True`
  - `geo_bypass: True` 
  - `prefer_insecure: True`

- **Web-Based Fallback**: Implemented web scraping fallbacks:
  - YouTube embed page parsing
  - Direct watch page extraction
  - Video info API as last resort

- **Better Format Selection**: Enhanced format selection logic to prefer audio-only formats and sort by quality

### 2. Enhanced Swift Implementation (`ViewModel.swift`)
- **Dual Extraction Strategy**: 
  1. First try Python helper with yt-dlp
  2. Fall back to Swift web-based extraction if Python fails

- **Swift Web Extraction**: Added native Swift methods:
  - `extractStreamURLFromWeb()` - Main web extraction coordinator
  - `tryYouTubeEmbed()` - Extract from embed pages
  - `tryYouTubeWatchPage()` - Extract from watch pages  
  - `tryVideoInfoAPI()` - Use video info endpoint
  - `extractPlayerResponse()` - Parse ytInitialPlayerResponse JSON
  - `extractStreamURL()` - Extract URLs from streaming data

- **Improved Error Handling**: Better error messages and graceful degradation

- **Automatic Updates**: Enhanced Python package management to automatically update yt-dlp to latest versions

## Key Features Added

### Multi-Method Extraction
1. **yt-dlp with multiple format strategies** (Primary)
2. **Web scraping YouTube embed pages** (Fallback 1)
3. **Web scraping YouTube watch pages** (Fallback 2)  
4. **YouTube video info API** (Fallback 3)

### Format Priority
1. Audio-only formats (preferred for music playback)
2. High bitrate audio formats
3. Any format with audio codec
4. Fallback to video formats with audio

### Better Resilience
- Automatic yt-dlp updates
- Multiple User-Agent strings
- Timeout handling
- Comprehensive error logging

## Test Results
Successfully tested with multiple video IDs including:
- `62yox0F5lcA` (Originally failing video)
- `dQw4w9WgXcQ` (Rick Astley - Never Gonna Give You Up)
- `kJQP7kiw5Fk` (Luis Fonsi - Despacito)
- `JGwWNGJdvx8` (Ed Sheeran - Shape of You)

All extractions now succeed and return valid stream URLs.

## Benefits
- ✅ Fixes the specific format availability error
- ✅ More robust against future YouTube changes  
- ✅ Better user experience with graceful fallbacks
- ✅ Improved error messages for debugging
- ✅ Maintains app performance with efficient fallback chain
