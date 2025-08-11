#!/usr/bin/env python3
import json
import os
import sys
from typing import Any, Dict, List, Optional

try:
    from ytmusicapi import YTMusic
except Exception as e:  # pragma: no cover
    print(json.dumps({"error": f"ytmusicapi not available: {e}"}))
    sys.exit(1)


def load_ytmusic() -> Optional[YTMusic]:
    """
    Try to load YTMusic with headers from common locations.
    Priority:
      1) headers_auth.json in same dir as this script (bundled resource for dev)
      2) ~/Library/Application Support/SpotlightMusic/headers_auth.json
      3) No headers (unauthenticated)
    """
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
    try:
        from yt_dlp import YoutubeDL
    except Exception as e:  # pragma: no cover
        print(json.dumps({"error": f"yt-dlp not available: {e}"}))
        return

    ydl_opts = {
        "format": "bestaudio[ext=m4a]/bestaudio/best",
        "quiet": True,
        "noplaylist": True,
        "nocheckcertificate": True,
    }
    url = f"https://www.youtube.com/watch?v={video_id}"
    try:
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            # Prefer a direct URL from the selected format
            if "url" in info:
                stream_url = info["url"]
            else:
                fmts = info.get("formats") or []
                # Choose the best audio format
                audio_fmts = [f for f in fmts if f.get("acodec") and f.get("vcodec") == "none"]
                audio_fmts.sort(key=lambda f: f.get("abr") or 0, reverse=True)
                stream_url = audio_fmts[0]["url"] if audio_fmts else None
            if not stream_url:
                print(json.dumps({"error": "No stream URL found"}))
                return
            print(json.dumps({"stream_url": stream_url}))
    except Exception as e:
        print(json.dumps({"error": f"Extraction failed: {e}"}))


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


