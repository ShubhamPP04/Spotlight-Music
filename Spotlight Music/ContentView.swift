//
//  ContentView.swift
//  Spotlight Music
//
//  Created by Shubham Kumar on 10/08/25.
//

import SwiftUI
import AVFoundation
import AppKit

struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var settings = SettingsManager.shared
    @FocusState private var isSearchFieldFocused: Bool
    
    // Energy-efficient hover animation helper
    private func energyEfficientHover(_ isHovered: Binding<Bool>) -> some View {
        return EmptyView().onHover { hovering in
            if settings.shouldEnableAnimations() {
                withAnimation(.easeOut(duration: 0.08)) {
                    isHovered.wrappedValue = hovering
                }
            } else {
                isHovered.wrappedValue = hovering
            }
        }
    }
    @State private var animatedHeight: CGFloat = 120
    @State private var expandedSongs = false
    @State private var expandedAlbums = false
    @State private var expandedArtists = false
    @State private var expandedVideos = false
    @State private var expandedArtistAlbums = false
    @State private var suppressNextAutoScroll = false
    
    private var targetHeight: CGFloat {
        let searchBarHeight: CGFloat = 76
        let sectionHeaderHeight: CGFloat = 32
        let rowHeight: CGFloat = 56
        let showAllButtonHeight: CGFloat = 32
        let maxHeight: CGFloat = 580
        let minHeight: CGFloat = 120
        let bottomPadding: CGFloat = 16
        let noResultsHeight: CGFloat = 40
        let headerHeight: CGFloat = 96 // For album/artist detail headers
        let backButtonHeight: CGFloat = 32
        
        var calculatedHeight = searchBarHeight + bottomPadding
        
        if viewModel.selectedAlbum != nil {
            // Album detail view
            calculatedHeight += backButtonHeight + headerHeight + sectionHeaderHeight + 8
            let songsCount = min(viewModel.albumSongs.count, 8)
            calculatedHeight += CGFloat(songsCount) * rowHeight
            if viewModel.isLoadingDetails {
                calculatedHeight += 60
            }
        } else if viewModel.selectedArtist != nil {
            // Artist detail view
            calculatedHeight += backButtonHeight + headerHeight
            let songsCount = min(viewModel.artistSongs.count, 6)
            let albumsCount = expandedArtistAlbums ? viewModel.artistAlbums.count : min(viewModel.artistAlbums.count, 4)
            if songsCount > 0 {
                calculatedHeight += sectionHeaderHeight + 8 + CGFloat(songsCount) * rowHeight
            }
            if albumsCount > 0 {
                calculatedHeight += sectionHeaderHeight + 8 + CGFloat(albumsCount) * rowHeight
                if viewModel.artistAlbums.count > 4 && !expandedArtistAlbums {
                    calculatedHeight += showAllButtonHeight
                }
            }
            if viewModel.isLoadingDetails {
                calculatedHeight += 60
            }
        } else if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Home view - show now playing and favorites if available
            if viewModel.nowPlaying != nil {
                calculatedHeight += sectionHeaderHeight + 8 + rowHeight // Now Playing section
            }
            if !viewModel.favoriteSongs.isEmpty {
                calculatedHeight += sectionHeaderHeight + 8 // Header + spacing
                let visibleFavorites = min(viewModel.favoriteSongs.count, 8)
                calculatedHeight += CGFloat(visibleFavorites) * rowHeight
            }
        } else {
            // Search results or searching state
            if viewModel.isSearching {
                calculatedHeight += 60 // Space for loading state
            } else {
                // Songs section
                if !viewModel.songs.isEmpty {
                    calculatedHeight += sectionHeaderHeight + 8
                    let songsToShow = expandedSongs ? viewModel.songs.count : min(viewModel.songs.count, 4)
                    calculatedHeight += CGFloat(songsToShow) * rowHeight
                    if viewModel.songs.count > 4 && !expandedSongs {
                        calculatedHeight += showAllButtonHeight
                    }
                }
                
                // Albums section
                if !viewModel.albums.isEmpty {
                    calculatedHeight += sectionHeaderHeight + 8
                    let albumsToShow = expandedAlbums ? viewModel.albums.count : min(viewModel.albums.count, 4)
                    calculatedHeight += CGFloat(albumsToShow) * rowHeight
                    if viewModel.albums.count > 4 && !expandedAlbums {
                        calculatedHeight += showAllButtonHeight
                    }
                }
                
                // Artists section
                if !viewModel.artists.isEmpty {
                    calculatedHeight += sectionHeaderHeight + 8
                    let artistsToShow = expandedArtists ? viewModel.artists.count : min(viewModel.artists.count, 4)
                    calculatedHeight += CGFloat(artistsToShow) * rowHeight
                    if viewModel.artists.count > 4 && !expandedArtists {
                        calculatedHeight += showAllButtonHeight
                    }
                }
                
                // Videos section
                if !viewModel.videos.isEmpty {
                    calculatedHeight += sectionHeaderHeight + 8
                    let videosToShow = expandedVideos ? viewModel.videos.count : min(viewModel.videos.count, 4)
                    calculatedHeight += CGFloat(videosToShow) * rowHeight
                    if viewModel.videos.count > 4 && !expandedVideos {
                        calculatedHeight += showAllButtonHeight
                    }
                }
                
                if viewModel.songs.isEmpty && viewModel.albums.isEmpty && viewModel.artists.isEmpty && viewModel.videos.isEmpty && !viewModel.query.isEmpty {
                    calculatedHeight += noResultsHeight
                }
            }
        }
        
        return min(max(calculatedHeight, minHeight), maxHeight)
    }

    var body: some View {
        mainContent
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .padding(12)
            .background(WindowConfigurator())
            .onChange(of: targetHeight) { _, newHeight in
                updateAnimatedHeight(newHeight)
            }
            .onChange(of: viewModel.query) { _, _ in
                resetExpandedStates()
            }
            .onChange(of: viewModel.nowPlaying?.id) { _, _ in
                if suppressNextAutoScroll {
                    suppressNextAutoScroll = false
                } else {
                    ensureVisibleNowPlaying()
                }
            }
            .onAppear {
                animatedHeight = targetHeight
                isSearchFieldFocused = true
            }
            .task { await viewModel.performSetupForPython() }
            .alert(item: errorBinding) { (item: IdentifiableString) in
                Alert(title: Text("Error"), message: Text(item.value))
            }
            .onKeyPress(.escape) {
                handleEscapeKey()
                return .handled
            }
    }
    
    private var mainContent: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                searchBar
                resultsPane
            }
            .padding(.bottom, 8)
            .frame(width: settings.windowSize.width, height: animatedHeight)
        }
    }
    
    private var errorBinding: Binding<IdentifiableString?> {
        Binding(
            get: { viewModel.errorMessage.map { IdentifiableString(value: $0) } },
            set: { _ in viewModel.errorMessage = nil }
        )
    }
    
    private func updateAnimatedHeight(_ newHeight: CGFloat) {
        if settings.shouldEnableAnimations() {
            // Use faster, less CPU-intensive animation
            withAnimation(.easeOut(duration: 0.15)) {
                animatedHeight = newHeight
            }
        } else {
            animatedHeight = newHeight
        }
    }
    
    private func resetExpandedStates() {
        expandedSongs = false
        expandedAlbums = false
        expandedArtists = false
        expandedVideos = false
        expandedArtistAlbums = false
    }

    private func ensureVisibleNowPlaying() {
        guard let nowId = viewModel.nowPlaying?.id else { return }
        // If the current song is inside the songs list but outside the collapsed view, auto-expand
        if !expandedSongs {
            if let idx = viewModel.songs.firstIndex(where: { $0.id == nowId }) {
                let collapsedLimit = min(viewModel.songs.count, 4)
                if idx >= collapsedLimit {
                    if settings.shouldEnableAnimations() {
                        withAnimation(.easeInOut(duration: 0.2)) { expandedSongs = true }
                    } else {
                        expandedSongs = true
                    }
                }
            }
        }
        // Same for videos section
        if !expandedVideos {
            if let vIdx = viewModel.videos.firstIndex(where: { $0.id == nowId }) {
                let collapsedLimit = min(viewModel.videos.count, 4)
                if vIdx >= collapsedLimit {
                    if settings.shouldEnableAnimations() {
                        withAnimation(.easeInOut(duration: 0.2)) { expandedVideos = true }
                    } else {
                        expandedVideos = true
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 18))
            TextField("Search songs, albums, artists", text: Binding(
                get: { viewModel.query },
                set: { viewModel.updateQuery($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .medium))
            .focused($isSearchFieldFocused)
            .onSubmit { Task { await viewModel.performSearch(viewModel.query) } }
            
            if !viewModel.query.isEmpty {
                Button(action: {
                    viewModel.updateQuery("")
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var resultsPane: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                if let selectedAlbum = viewModel.selectedAlbum {
                    // Album detail view
                    albumDetailView(selectedAlbum)
                } else if let selectedArtist = viewModel.selectedArtist {
                    // Artist detail view
                    artistDetailView(selectedArtist)
                } else if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Home view
                    if let nowPlaying = viewModel.nowPlaying {
                        SectionHeader("Now Playing")
                        SongRow(item: nowPlaying, isActive: true, isFavorite: viewModel.isFavorite(nowPlaying), onPlay: {
                            // Already playing, could pause/resume here
                        }, onToggleFavorite: {
                            viewModel.toggleFavorite(nowPlaying)
                        })
                        .id("now:\(nowPlaying.id)")
                    }
                    
                    if !viewModel.favoriteSongs.isEmpty {
                        SectionHeader("Home · Favorites")
                        ForEach(Array(viewModel.favoriteSongs.prefix(8).enumerated()), id: \.element.id) { index, item in
                            SongRow(item: item, isActive: viewModel.nowPlaying?.id == item.id, isFavorite: true, onPlay: {
                                // Ensure we don't auto-scroll away when playing from favorites
                                suppressNextAutoScroll = true
                                // Play from the full favorites list and compute the correct index within it
                                let fullFavorites = Array(viewModel.favoriteSongs)
                                let fullIndex = fullFavorites.firstIndex(where: { $0.id == item.id }) ?? index
                                viewModel.play(song: item, fromPlaylist: fullFavorites, atIndex: fullIndex)
                            }, onToggleFavorite: {
                                viewModel.toggleFavorite(item)
                            })
                            .id("fav:\(item.id)")
                        }
                    }
                } else {
                    // Search results
                    if viewModel.isSearching {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Searching...")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    } else {
                        searchResultsContent
                        
                        if viewModel.songs.isEmpty && viewModel.albums.isEmpty && viewModel.artists.isEmpty && !viewModel.query.isEmpty {
                            Text("No results")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                    }
                }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: animatedHeight - 92) // Dynamic max height based on window size
            .onChange(of: viewModel.nowPlaying?.id) { _, newId in
                guard let id = newId else { return }
                let animate = settings.shouldEnableAnimations()
                if animate {
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                } else {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
    
    @ViewBuilder
    private var searchResultsContent: some View {
        // Songs section
        if !viewModel.songs.isEmpty {
            SectionHeader("Songs")
            let songsToShow = expandedSongs ? viewModel.songs.count : min(viewModel.songs.count, 4)
            ForEach(Array(viewModel.songs.prefix(songsToShow).enumerated()), id: \.element.id) { index, item in
                SongRow(item: item, isActive: viewModel.nowPlaying?.id == item.id, isFavorite: viewModel.isFavorite(item), onPlay: {
                    viewModel.play(song: item, fromPlaylist: viewModel.songs, atIndex: index)
                }, onToggleFavorite: {
                    viewModel.toggleFavorite(item)
                })
                .id(item.id)
            }
            if viewModel.songs.count > 4 && !expandedSongs {
                ShowAllButton(count: viewModel.songs.count, type: "Songs") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        expandedSongs = true
                    }
                }
            }
        }
        
        // Albums section
        if !viewModel.albums.isEmpty {
            SectionHeader("Albums")
            let albumsToShow = expandedAlbums ? viewModel.albums.count : min(viewModel.albums.count, 4)
            ForEach(viewModel.albums.prefix(albumsToShow)) { album in
                AlbumRow(album: album, onTap: {
                    Task { await viewModel.showAlbumDetails(album) }
                })
            }
            if viewModel.albums.count > 4 && !expandedAlbums {
                ShowAllButton(count: viewModel.albums.count, type: "Albums") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        expandedAlbums = true
                    }
                }
            }
        }
        
        // Artists section
        if !viewModel.artists.isEmpty {
            SectionHeader("Artists")
            let artistsToShow = expandedArtists ? viewModel.artists.count : min(viewModel.artists.count, 4)
            ForEach(viewModel.artists.prefix(artistsToShow)) { artist in
                ArtistRow(artist: artist, onTap: {
                    Task { await viewModel.showArtistDetails(artist) }
                })
            }
            if viewModel.artists.count > 4 && !expandedArtists {
                ShowAllButton(count: viewModel.artists.count, type: "Artists") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        expandedArtists = true
                    }
                }
            }
        }
        
        // Videos section
        if !viewModel.videos.isEmpty {
            SectionHeader("Videos")
            let videosToShow = expandedVideos ? viewModel.videos.count : min(viewModel.videos.count, 4)
            ForEach(Array(viewModel.videos.prefix(videosToShow).enumerated()), id: \.element.id) { index, video in
                VideoRow(video: video, isActive: viewModel.nowPlaying?.id == video.id, onPlay: {
                    viewModel.play(video: video, fromPlaylist: viewModel.videos, atIndex: index)
                })
                .id(video.id)
            }
            if viewModel.videos.count > 4 && !expandedVideos {
                ShowAllButton(count: viewModel.videos.count, type: "Videos") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        expandedVideos = true
                    }
                }
            }
        }
        
        if viewModel.songs.isEmpty && viewModel.albums.isEmpty && viewModel.artists.isEmpty && viewModel.videos.isEmpty && !viewModel.query.isEmpty {
            Text("No results")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }
    
    private func handleEscapeKey() {
        // If we're in a detail view (album or artist), go back to search results
        if viewModel.selectedAlbum != nil || viewModel.selectedArtist != nil {
            viewModel.clearDetails()
        }
        // If we're in search results with a query, clear the search to go to home
        else if !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.updateQuery("")
        }
        // If we're already at home, do nothing (or could minimize/hide the app)
    }
    
    @ViewBuilder
    private func albumDetailView(_ album: AlbumItem) -> some View {
        // Back button
        Button(action: { viewModel.clearDetails() }) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Back")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        
        // Album header
        HStack(spacing: 16) {
            AsyncImage(url: album.thumbnail.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: { 
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                    .overlay(
                        Image(systemName: "opticaldisc")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 24))
                    )
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)
                if let artist = album.artist {
                    Text(artist)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                if let year = album.year {
                    Text(year)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        
        if viewModel.isLoadingDetails {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading album...")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        } else {
            // Album songs
            if !viewModel.albumSongs.isEmpty {
                SectionHeader("Songs")
                ForEach(Array(viewModel.albumSongs.enumerated()), id: \.element.id) { index, song in
                    SongRow(item: song, isActive: viewModel.nowPlaying?.id == song.id, isFavorite: viewModel.isFavorite(song), onPlay: {
                        viewModel.play(song: song, fromPlaylist: viewModel.albumSongs, atIndex: index)
                    }, onToggleFavorite: {
                        viewModel.toggleFavorite(song)
                    })
                    .id(song.id)
                }
            }
        }
    }
    
    @ViewBuilder
    private func artistDetailView(_ artist: ArtistItem) -> some View {
        // Back button
        Button(action: { viewModel.clearDetails() }) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Back")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        
        // Artist header
        HStack(spacing: 16) {
            AsyncImage(url: artist.thumbnail.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: { 
                Circle()
                    .fill(.quaternary)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 24))
                    )
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)
                if let subs = artist.subscribers {
                    Text(subs)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        
        if viewModel.isLoadingDetails {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading artist...")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        } else {
            // Top songs
            if !viewModel.artistSongs.isEmpty {
                SectionHeader("Top Songs")
                ForEach(Array(viewModel.artistSongs.enumerated()), id: \.element.id) { index, song in
                    SongRow(item: song, isActive: viewModel.nowPlaying?.id == song.id, isFavorite: viewModel.isFavorite(song), onPlay: {
                        viewModel.play(song: song, fromPlaylist: viewModel.artistSongs, atIndex: index)
                    }, onToggleFavorite: {
                        viewModel.toggleFavorite(song)
                    })
                    .id(song.id)
                }
            }
            
            // Albums
            if !viewModel.artistAlbums.isEmpty {
                SectionHeader("Albums")
                let albumsToShow = expandedArtistAlbums ? viewModel.artistAlbums.count : min(viewModel.artistAlbums.count, 4)
                ForEach(viewModel.artistAlbums.prefix(albumsToShow)) { album in
                    AlbumRow(album: album, onTap: {
                        Task { await viewModel.showAlbumDetails(album) }
                    })
                }
                if viewModel.artistAlbums.count > 4 && !expandedArtistAlbums {
                    ShowAllButton(count: viewModel.artistAlbums.count, type: "Albums") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            expandedArtistAlbums = true
                        }
                    }
                }
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

private struct ShowAllButton: View {
    let count: Int
    let type: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("Show all \(count) \(type.lowercased())")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // Energy-efficient hover with shorter duration
            if SettingsManager.shared.shouldEnableAnimations() {
                withAnimation(.easeOut(duration: 0.08)) {
                    isHovered = hovering
                }
            } else {
                isHovered = hovering
            }
        }
    }
}

private struct SongRow: View {
    let item: SongItem
    let isActive: Bool
    let isFavorite: Bool
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                if SettingsManager.shared.shouldShowThumbnails() {
                    AsyncImage(url: item.thumbnail.flatMap(URL.init(string:))) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure(_), .empty:
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 16))
                                )
                        @unknown default:
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 16))
                        )
                        .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(isActive ? .primary : .primary)
                    HStack(spacing: 4) {
                        if let artists = item.artists, !artists.isEmpty { 
                            Text(artists).foregroundStyle(.secondary) 
                        }
                        if let album = item.album, !album.isEmpty { 
                            Text("·").foregroundStyle(.tertiary)
                            Text(album).foregroundStyle(.secondary) 
                        }
                        if let duration = item.duration, !duration.isEmpty { 
                            Text("·").foregroundStyle(.tertiary)
                            Text(duration).foregroundStyle(.secondary) 
                        }
                    }.font(.system(size: 13)).lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorite ? .red : .secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered || isFavorite ? 1.0 : 0.0)
                    
                    if isActive { 
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.blue.opacity(0.1) : (isHovered ? Color.primary.opacity(0.04) : .clear))
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.08)) {
                    isHovered = hovering
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AlbumRow: View {
    let album: AlbumItem
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if SettingsManager.shared.shouldShowThumbnails() {
                    AsyncImage(url: album.thumbnail.flatMap(URL.init(string:))) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure(_), .empty:
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary)
                                .overlay(
                                    Image(systemName: "opticaldisc")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 16))
                                )
                        @unknown default:
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .overlay(
                            Image(systemName: "opticaldisc")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 16))
                        )
                        .frame(width: 44, height: 44)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let artist = album.artist { 
                            Text(artist).foregroundStyle(.secondary) 
                        }
                        if let year = album.year { 
                            Text("·").foregroundStyle(.tertiary)
                            Text(year).foregroundStyle(.secondary) 
                        }
                    }.font(.system(size: 13)).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.04) : .clear)
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.08)) {
                    isHovered = hovering
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ArtistRow: View {
    let artist: ArtistItem
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if SettingsManager.shared.shouldShowThumbnails() {
                    AsyncImage(url: artist.thumbnail.flatMap(URL.init(string:))) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { 
                        Circle()
                            .fill(.quaternary)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 16))
                            )
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(.quaternary)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 16))
                        )
                        .frame(width: 44, height: 44)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                    if let subs = artist.subscribers { 
                        Text(subs)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.04) : .clear)
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.08)) {
                    isHovered = hovering
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct VideoRow: View {
    let video: VideoItem
    let isActive: Bool
    let onPlay: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                if SettingsManager.shared.shouldShowThumbnails() {
                    AsyncImage(url: video.thumbnail.flatMap(URL.init(string:))) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure(_), .empty:
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary)
                                .overlay(
                                    Image(systemName: "play.rectangle")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 16))
                                )
                        @unknown default:
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .overlay(
                            Image(systemName: "play.rectangle")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 16))
                        )
                        .frame(width: 44, height: 44)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(isActive ? .primary : .primary)
                    HStack(spacing: 4) {
                        if let artists = video.artists, !artists.isEmpty { 
                            Text(artists).foregroundStyle(.secondary) 
                        }
                        if let views = video.views, !views.isEmpty { 
                            Text("·").foregroundStyle(.tertiary)
                            Text(views).foregroundStyle(.secondary) 
                        }
                        if let duration = video.duration, !duration.isEmpty { 
                            Text("·").foregroundStyle(.tertiary)
                            Text(duration).foregroundStyle(.secondary) 
                        }
                    }.font(.system(size: 13)).lineLimit(1)
                }
                
                Spacer()
                
                if isActive { 
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.blue.opacity(0.1) : (isHovered ? Color.primary.opacity(0.04) : .clear))
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.08)) {
                    isHovered = hovering
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
