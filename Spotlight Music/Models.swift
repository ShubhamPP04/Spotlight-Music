import Foundation

struct SongItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artists: String?
    let album: String?
    let duration: String?
    let thumbnail: String?
}

struct AlbumItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artist: String?
    let year: String?
    let thumbnail: String?
}

struct ArtistItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let subscribers: String?
    let thumbnail: String?
}

struct VideoItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artists: String?
    let duration: String?
    let thumbnail: String?
    let views: String?
}

struct SearchAllResponse: Codable {
    let songs: [SongItem]
    let albums: [AlbumItem]
    let artists: [ArtistItem]
    let videos: [VideoItem]
}



