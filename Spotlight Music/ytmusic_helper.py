#!/usr/bin/env python3
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional

try:
    from ytmusicapi import YTMusic
except Exception as e:  # pragma: no cover
    print(json.dumps({"error": f"ytmusicapi not available: {e}"}))
    sys.exit(1)

# Configuration for yt-dlp update tracking
UPDATE_INTERVAL = 24 * 60 * 60  # 24 hours in seconds
UPDATE_TIMESTAMP_FILE = os.path.expanduser("~/Library/Application Support/SpotlightMusic/.ytdlp_last_update")

def should_update_ytdlp():
    """Check if yt-dlp should be updated based on last update time."""
    if not os.path.exists(UPDATE_TIMESTAMP_FILE):
        return True
    
    try:
        with open(UPDATE_TIMESTAMP_FILE, 'r') as f:
            last_update = float(f.read().strip())
            return (time.time() - last_update) > UPDATE_INTERVAL
    except (ValueError, FileNotFoundError):
        return True

def mark_ytdlp_updated():
    """Mark yt-dlp as updated by saving current timestamp."""
    os.makedirs(os.path.dirname(UPDATE_TIMESTAMP_FILE), exist_ok=True)
    with open(UPDATE_TIMESTAMP_FILE, 'w') as f:
        f.write(str(time.time()))


def should_update_ytdlp():
    """Check if yt-dlp should be updated (only on first run or if last update was >24h ago)."""
    import os
    import time
    from pathlib import Path
    
    # Create timestamp file path in user's home directory
    timestamp_file = Path.home() / ".spotlight_music_ytdlp_update"
    
    try:
        if not timestamp_file.exists():
            return True  # First run
        
        # Check if last update was more than 24 hours ago
        last_update = timestamp_file.stat().st_mtime
        current_time = time.time()
        hours_since_update = (current_time - last_update) / 3600
        
        return hours_since_update > 24
    except Exception:
        return True  # If we can't check, assume we should update

def mark_ytdlp_updated():
    """Mark yt-dlp as updated by creating/updating timestamp file."""
    import time
    from pathlib import Path
    
    try:
        timestamp_file = Path.home() / ".spotlight_music_ytdlp_update"
        timestamp_file.touch()
    except Exception:
        pass  # Silently fail if we can't create timestamp file

def load_ytmusic():
    """Load YTMusic API with error handling."""
    script_dir = os.path.dirname(os.path.realpath(__file__))
    local_headers = os.path.join(script_dir, "headers_auth.json")
    app_support_headers = os.path.expanduser(
        "~/Library/Application Support/SpotlightMusic/headers_auth.json"
    )

    try:
        if os.path.exists(local_headers):
            return YTMusic(local_headers)
        if os.path.exists(app_support_headers):
            return YTMusic(app_support_headers)
        # Fallback: unauthenticated
        return YTMusic()
    except Exception as e:
        print(json.dumps({"error": f"Failed to initialize YTMusic: {e}"}))
        return None


def simplify_song(item: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Extract a simplified song record from ytmusicapi search result."""
    try:
        if item.get("resultType") not in ("song", "video"):
            return None
        video_id = item.get("videoId")
        if not video_id:
            return None
        title = item.get("title") or ""
        artists = item.get("artists") or []
        artist_names = ", ".join([a.get("name", "") for a in artists if isinstance(a, dict)])
        album = (item.get("album") or {}).get("name") if isinstance(item.get("album"), dict) else None
        duration = item.get("duration") or item.get("length")
        thumbnails = item.get("thumbnails") or []
        thumbnail_url = thumbnails[-1]["url"] if thumbnails else None
        return {
            "id": video_id,
            "videoId": video_id,
            "title": title,
            "artists": artist_names,
            "album": album,
            "duration": duration,
            "thumbnail": thumbnail_url,
        }
    except Exception:
        return None


def handle_search(query: str) -> None:
    ytm = load_ytmusic()
    if ytm is None:
        return
    try:
        results = ytm.search(query, filter="songs")
        # Fallback: broader search if no songs
        if not results:
            results = ytm.search(query)
        simplified: List[Dict[str, Any]] = []
        for item in results or []:
            simple = simplify_song(item)
            if simple:
                simplified.append(simple)
        print(json.dumps({"results": simplified}))
    except Exception as e:
        print(json.dumps({"error": f"Search failed: {e}"}))


def handle_stream_url(video_id: str) -> None:
    """Extract stream URL with fallback methods and smart yt-dlp updating."""
    
    def try_extraction():
        """Try extraction with current yt-dlp version."""
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
                        "ignoreerrors": True,
                        "no_check_certificate": True,
                        "geo_bypass": True,
                        "prefer_insecure": True
                    }
                    
                    with YoutubeDL(ydl_opts) as ydl:
                        info = ydl.extract_info(url, download=False)
                        
                        # Multiple ways to get stream URL
                        stream_url = None
                        
                        if "url" in info and info["url"]:
                            stream_url = info["url"]
                        elif "formats" in info:
                            fmts = info.get("formats", [])
                            
                            # Prefer audio-only formats
                            audio_fmts = [f for f in fmts if f.get("acodec") != "none" and f.get("vcodec") == "none"]
                            if audio_fmts:
                                audio_fmts.sort(key=lambda f: f.get("abr", 0), reverse=True)
                                stream_url = audio_fmts[0].get("url")
                            
                            # Fallback to any format with audio
                            if not stream_url:
                                audio_any = [f for f in fmts if f.get("acodec") != "none" and f.get("url")]
                                if audio_any:
                                    audio_any.sort(key=lambda f: f.get("abr", 0), reverse=True)
                                    stream_url = audio_any[0]["url"]
                        
                        if stream_url:
                            return stream_url
                            
                except Exception:
                    continue
        except ImportError:
            pass
        return None
    
    def try_web_extraction():
        """Try web-based extraction as fallback."""
        try:
            import urllib.request
            import urllib.parse
            import re
            
            # Try YouTube embed page
            embed_url = f"https://www.youtube.com/embed/{video_id}"
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
            }
            
            request = urllib.request.Request(embed_url, headers=headers)
            with urllib.request.urlopen(request, timeout=10) as response:
                html = response.read().decode('utf-8')
                
                # Extract player config
                player_match = re.search(r'ytInitialPlayerResponse\s*=\s*({.+?});', html)
                if player_match:
                    player_data = json.loads(player_match.group(1))
                    
                    streaming_data = player_data.get('streamingData', {})
                    formats = streaming_data.get('formats', []) + streaming_data.get('adaptiveFormats', [])
                    
                    # Find audio format
                    for fmt in formats:
                        if fmt.get('mimeType', '').startswith('audio/') and fmt.get('url'):
                            return fmt['url']
        except Exception:
            pass
        return None
    
    def update_ytdlp():
        """Update yt-dlp to latest version."""
        try:
            import subprocess
            import sys
            result = subprocess.run([sys.executable, "-m", "pip", "install", "--upgrade", "--user", "yt-dlp"], 
                                  capture_output=True, text=True)
            return result.returncode == 0
        except Exception:
            return False
    
    # First attempt: Try extraction with current yt-dlp
    stream_url = try_extraction()
    if stream_url:
        print(json.dumps({"stream_url": stream_url}))
        return
    
    # Second attempt: Try web extraction
    stream_url = try_web_extraction()
    if stream_url:
        print(json.dumps({"stream_url": stream_url}))
        return
    
    # Third attempt: Update yt-dlp if it hasn't been updated recently, then retry
    if should_update_ytdlp():
        if update_ytdlp():
            mark_ytdlp_updated()
            # Retry extraction after update
            stream_url = try_extraction()
            if stream_url:
                print(json.dumps({"stream_url": stream_url}))
                return
    
    # Final fallback: Try YouTube Music direct if available
    try:
        ytm = load_ytmusic()
        if ytm:
            song_info = ytm.get_song(video_id)
            if song_info and 'streamingData' in song_info:
                formats = song_info['streamingData'].get('adaptiveFormats', [])
                for fmt in formats:
                    if fmt.get('mimeType', '').startswith('audio/') and fmt.get('url'):
                        print(json.dumps({"stream_url": fmt['url']}))
                        return
    except Exception:
        pass
    
    print(json.dumps({"error": f"Could not extract stream URL for video {video_id}. All methods failed."}))


def main() -> None:
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: ytmusic_helper.py [search <query> | stream_url <video_id>]"}))
        return
    command = sys.argv[1]
    if command == "search":
        query = " ".join(sys.argv[2:]).strip()
        handle_search(query)
    elif command == "stream_url":
        video_id = sys.argv[2]
        handle_stream_url(video_id)
    else:
        print(json.dumps({"error": f"Unknown command: {command}"}))


if __name__ == "__main__":
    main()


