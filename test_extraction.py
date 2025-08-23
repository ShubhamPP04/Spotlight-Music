#!/usr/bin/env python3

"""Test script to verify YouTube audio extraction fixes."""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'Spotlight Music'))

from ytmusic_helper import handle_stream_url

def test_extraction(video_id):
    """Test the enhanced extraction method."""
    print(f"Testing extraction for video ID: {video_id}")
    
    try:
        handle_stream_url(video_id)
    except Exception as e:
        print(f"Error during extraction: {e}")

if __name__ == "__main__":
    # Test with the problematic video ID
    test_video_id = "62yox0F5lcA"
    test_extraction(test_video_id)
    
    # Test with a few more IDs to ensure robustness
    additional_test_ids = [
        "dQw4w9WgXcQ",  # Rick Astley - Never Gonna Give You Up
        "kJQP7kiw5Fk",  # Luis Fonsi - Despacito
        "JGwWNGJdvx8"   # Ed Sheeran - Shape of You
    ]
    
    print("\nTesting additional video IDs:")
    for vid in additional_test_ids:
        print(f"\n--- Testing {vid} ---")
        test_extraction(vid)
