//
//  EtoileLibrary.swift
//  EtoileKit
//
//  Created by Juliette Bernheisel on 8/30/24.
//

import Foundation
import Cache
import SimpleKeychain
import JellyfinAPI
import OSLog

public class EtoileLibrary {
    private var albums: [Album] = []
    private var songs: [String: [Song]] = [:]
    private var albumStorage: Storage<String, [Album]>? = nil /// `["albums"]` = `[Albums]` in library
    private var songStorage: Storage<String, [Song]>? = nil /// `["album id"]` = `[Song]` in album
    private var client: JellyfinClient? = nil
    var playlistsStorage: Storage<String, [Playlist]>? = nil /// `["playlists"]` = `[Playlist]` in library
    var playlistsSongsStorage: Storage<String, [Song]>? = nil /// `["playlist id"]` = `[Song]` in playlist
    
    public init() {}
    
    /// Gets artwork for item
    fileprivate func getArt(item: BaseItemDto) async -> Data? {
        // Incase the artist does not have an image we just continue going on
        do {
            let imagesPath = Paths.getItemImage(itemID: item.id ?? "", imageType: "Primary")
            let image = try await client?.send(imagesPath)
            return image?.value
        } catch {
            Logger().warning("\(#file):\(#line) > Error getting image \n \(error) \n ========")
        }
        return nil
    }
    
    /// Gets all the users libraries (of music type) and returns the id list
    fileprivate func getLibraries() async throws -> [String] {
        let viewsPath = Paths.getUserViews()
        let data = try await client?.send(viewsPath)
        var libraries: [String] = []
        for item in data?.value.items ?? [] {
            if item.collectionType == .music {
                guard let indexNumber = item.id else { continue }
                libraries.append(indexNumber)
            }
        }
        
        return libraries
    }
    
    /// Gets albums from artist id
    public func getAlbums(artistId: String) async throws -> [Album] {
        // Send request
        let albumsPath = Paths.getItems(parameters:  Paths.GetItemsParameters(parentID: artistId))
        let albumsResponse = try await client?.send(albumsPath)
        
        // Create empty array that we append to
        var albums: [Album] = []
        for albumItem in albumsResponse?.value.items ?? [] {
            guard let name = albumItem.name, let id = albumItem.id, let artist = albumItem.albumArtist else { continue }
            
            let image = await getArt(item: albumItem)
            let album = Album(name: name, artist: artist, art: image, id: id)
            albums.append(album)
        }
        
        return albums
    }
    
    /// Gets songs in the album
    public func getSongsInAlbum(albumId: String, deviceName: String) async throws -> [Song] {
        // Setup client
        if client == nil {
            let keychain = SimpleKeychain(service: "etoile")
            let instanceAsString = try keychain.string(forKey: "instance")
            guard let instance = URL(string: instanceAsString) else { throw EtoileBasicErrors.whatTheFuck }
            let token = try keychain.string(forKey: "token")
            
            let configuration = JellyfinClient.Configuration(url: instance, client: "Etoile", deviceName: deviceName, deviceID: UUID().uuidString, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            let jellyfinClient = JellyfinClient(configuration: configuration, accessToken: token)
            self.client = jellyfinClient
        }
        
        
        // Send request
        let path = Paths.getItems(parameters: Paths.GetItemsParameters(parentID: albumId))
        let response = try await client?.send(path)
        
        var songs: [Song] = []
        
        if response == nil {
            throw EtoileBasicErrors.whatTheFuck
        }
        
        // Gives the songs in the album
        for songItem in response?.value.items ?? [] {
            guard let name = songItem.name, let artist = songItem.albumArtist, let id = songItem.id else { continue }
            let image = await getArt(item: songItem)
            let song = Song(name: name, artist: artist, id: id, art: image, positionInAlbum: Int64(songItem.indexNumber ?? 0))
            songs.append(song)
        }
        
        // Save to songs cache
        guard let songStorageSafe = songStorage else { throw EtoileBasicErrors.whatTheFuck }
        try songStorageSafe.setObject(songs, forKey: albumId)
        
        return songs
    }
    
    /// Gets all the artists in all of the user's libraries
    private func getArtists() async throws -> [Artist] {
        // Getting libraries
        let libraries = try await getLibraries()
        
        // Let's make this better to use....
        // I love jellyfin but BasicDTO is a bitch because it has SO MUCH
        var artists: [Artist] = []
        
        // Getting media from (music) libraries
        // Most users should have one library but for Libraries Georg we check all their (music) libraries
        for library in libraries {
            // Send request
            let mediaPath = Paths.getItems(parameters: Paths.GetItemsParameters(parentID: library))
            let data = try await client?.send(mediaPath)
            let unwrapped = data?.value
            
            
            for item in unwrapped?.items ?? [] {
                if item.type == .musicArtist {
                    guard let id = item.id, let artistName = item.name else { continue }
                    let image = await getArt(item: item)
                    
                    // Simple swifty object that we add to our list:)
                    let artist = Artist(id: id, name: artistName, image: image)
                    artists.append(artist)
                }
            }
        }
        return artists
    }
    
    /// Reloads albums from Jellyfin
    private func reloadAlbumsFromFin() async throws {
        Logger().info("Getting library from Jellyfin")
        albums = []
        
        let artists = try await getArtists()
        for artist in artists {
            do {
                let albumsFromArtist = try await getAlbums(artistId: artist.id)
                albums.append(contentsOf: albumsFromArtist)
            } catch {
                Logger().error("Error getting albums from artist: \(artist.name), working around by ignoring this error \(error)")
            }
        }
        
        if albumStorage == nil {
            try setupCache()
        }
        
        guard let albumStorageSafe = albumStorage else { throw EtoileBasicErrors.whatTheFuck }
        
        try albumStorageSafe.setObject(albums, forKey: "albums")
    }
    
    /// Reloads songs from Jellyfin, this gets ALL songs from a specific album
    public func reloadSongsFromFin(album: Album, deviceName: String) async throws {
        Logger().info("Getting library from Jellyfin")
        songs = [:]
        
        if songStorage == nil {
            try setupCache()
        }
        
        guard let songStorageSafe = songStorage else { throw EtoileBasicErrors.whatTheFuck }
        
        let songsFromAlbum = try await getSongsInAlbum(albumId: album.id, deviceName: deviceName)
        try songStorageSafe.setObject(songsFromAlbum, forKey: album.id)
        songs[album.id] = songsFromAlbum
    }
    
    /// Set songs and albums to cache (used on Apple Watch)
    public func setAlbumsAndCache(albums: [Album]?, songs: [String: [Song]]?) throws {
        // Setting songs
        if songStorage == nil {
            try setupCache()
        }
        guard let songStorageSafe = songStorage else { throw EtoileBasicErrors.whatTheFuck }
        
        if let safeSongs = songs {
            for song in safeSongs {
                try songStorageSafe.setObject(song.value, forKey: song.key)
            }
            
        }
        
        if let safeAlbums = albums {
            // Setting albums
            if albumStorage == nil {
                try setupCache()
            }
            
            guard let albumStorageSafe = albumStorage else { throw EtoileBasicErrors.whatTheFuck }
            try albumStorageSafe.setObject(safeAlbums, forKey: "albums")
        }
    }
    
    /// Sets up cache for storage, should be called if `albumStorage` or `songStorage` is nil
    fileprivate func setupCache() throws {
        // Setup cache for albums
        let albumsDiskConfig = DiskConfig(name: "etoileAlbums")
        let expiry = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        let albumMemoryConfig = MemoryConfig(expiry: .date(expiry), countLimit: 10, totalCostLimit: 10)
        
        albumStorage = try Storage<String, [Album]>(
            diskConfig: albumsDiskConfig,
            memoryConfig: albumMemoryConfig, fileManager: FileManager.default,
            transformer: TransformerFactory.forCodable(ofType: [Album].self)
        )
        
        // Setup cache for songs
        let songsDiskConfig = DiskConfig(name: "etoileSongs")
        let songsMemoryConfig = MemoryConfig(expiry: .date(expiry), countLimit: 10, totalCostLimit: 10)
        songStorage = try Storage<String, [Song]>(
            diskConfig: songsDiskConfig,
            memoryConfig: songsMemoryConfig, fileManager: FileManager.default,
            transformer: TransformerFactory.forCodable(ofType: [Song].self)
        )
        
        // Playlists
        let playlistsDiskConfig = DiskConfig(name: "etoilePlaylists")
        let playlistsMemoryConfig = MemoryConfig(expiry: .date(expiry), countLimit: 10, totalCostLimit: 10)
        
        playlistsStorage = try Storage<String, [Playlist]>(
            diskConfig: playlistsDiskConfig,
            memoryConfig: playlistsMemoryConfig, fileManager: FileManager.default,
            transformer: TransformerFactory.forCodable(ofType: [Playlist].self)
        )
        
        // Playlist songs
        let playlistsSongsDiskConfig = DiskConfig(name: "etoilePlaylistsSongs")
        let playlistsSongsMemoryConfig = MemoryConfig(expiry: .date(expiry), countLimit: 10, totalCostLimit: 10)
        
        playlistsSongsStorage = try Storage<String, [Song]>(
            diskConfig: playlistsSongsDiskConfig,
            memoryConfig: playlistsSongsMemoryConfig, fileManager: FileManager.default,
            transformer: TransformerFactory.forCodable(ofType: [Song].self)
        )
        
    }
    
    /// Get recently played
    public func getRecentlyPlayed() throws -> [Song] {
        let recentlyPlayedDiskConfig = DiskConfig(name: "etoileRecentlyPlayedSongs")
        let expiry = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        let recentlyPlayedMemoryConfig = MemoryConfig(expiry: .date(expiry), countLimit: 10, totalCostLimit: 10)
        let recentlyPlayedStorage = try Storage<String, [Song]>(
            diskConfig: recentlyPlayedDiskConfig,
            memoryConfig: recentlyPlayedMemoryConfig, fileManager: FileManager.default,
            transformer: TransformerFactory.forCodable(ofType: [Song].self)
        )
        
        return try recentlyPlayedStorage.object(forKey: "recentlyPlayed")
    }
    
    public func addToRecentlyPlayed(song: Song) throws {
        let recentlyPlayedDiskConfig = DiskConfig(name: "etoileRecentlyPlayedSongs")
        let expiry = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        let recentlyPlayedMemoryConfig = MemoryConfig(expiry: .date(expiry), countLimit: 10, totalCostLimit: 10)
        let recentlyPlayedStorage = try Storage<String, [Song]>(
            diskConfig: recentlyPlayedDiskConfig,
            memoryConfig: recentlyPlayedMemoryConfig, fileManager: FileManager.default,
            transformer: TransformerFactory.forCodable(ofType: [Song].self)
        )
        
        do {
            var newValue = try recentlyPlayedStorage.object(forKey: "recentlyPlayed")
            newValue.insert(song, at: 0)
            try recentlyPlayedStorage.setObject(newValue, forKey: "recentlyPlayed")
        } catch {
            let newValue = [song]
            try recentlyPlayedStorage.setObject(newValue, forKey: "recentlyPlayed")
        }
    }
    
    /// Reloads data from cache, returns a tuple with 0 being list of albums and 1 being the songs with album
    public func reload(deviceName: String) async throws -> ([Album], [String: [Song]]) {
        
        if client == nil {
            let keychain = SimpleKeychain(service: "etoile")
            let instanceAsString = try keychain.string(forKey: "instance")
            guard let instance = URL(string: instanceAsString) else { throw EtoileBasicErrors.whatTheFuck }
            let token = try keychain.string(forKey: "token")
            
            let configuration = JellyfinClient.Configuration(url: instance, client: "Etoile", deviceName: deviceName, deviceID: UUID().uuidString, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            let jellyfinClient = JellyfinClient(configuration: configuration, accessToken: token)
            self.client = jellyfinClient
        }
        
        if songStorage == nil || albumStorage == nil {
            try setupCache()
        }
        
        guard let songStorageSafe = songStorage else { throw EtoileBasicErrors.whatTheFuck }
        guard let albumStorageSafe = albumStorage else { throw EtoileBasicErrors.whatTheFuck }
        
        do {
            albums = try albumStorageSafe.object(forKey: "albums")
            Logger().info("Got albums from cache")
            
            songs = [:]
            
            for album in albums {
                do {
                    let songsInAlbum = try songStorageSafe.object(forKey: album.id)
                    songs[album.id] = songsInAlbum
                } catch {
                    Logger().error("Error getting songs in album \(album.name) working around by ignoring this error \(error)")
                    continue
                }
            }
            
            return (albums, songs)
        } catch {
            try await reloadAlbumsFromFin()
            
            return (albums, songs)
        }
    }
    
    /// Reloads data from cache, returns a tuple with 0 being list of albums and 1 being the songs with album
    public func reloadNoPull() throws -> ([Album], [String: [Song]])? {
        
        if songStorage == nil || albumStorage == nil {
            try setupCache()
        }
        
        guard let songStorageSafe = songStorage else { throw EtoileBasicErrors.whatTheFuck }
        guard let albumStorageSafe = albumStorage else { throw EtoileBasicErrors.whatTheFuck }
        
        do {
            self.albums = try albumStorageSafe.object(forKey: "albums")
            Logger().info("Got albums from cache")
            
            self.songs = [:]
            
            for album in albums {
                do {
                    let songsInAlbum = try songStorageSafe.object(forKey: album.id)
                    self.songs[album.id] = songsInAlbum
                } catch {
                    continue
                }
            }
            
            return (self.albums, self.songs)
        } catch {
            Logger().info("ERROR \(error)")
            return nil
        }
    }
    
    
    /// Refreshes data from jellyfin, returns a tuple with 0 being list of albums and 1 being the songs with album
    public func refresh(deviceName: String) async throws -> ([Album], [String: [Song]]){
        if client == nil {
            let keychain = SimpleKeychain(service: "etoile")
            let instanceAsString = try keychain.string(forKey: "instance")
            guard let instance = URL(string: instanceAsString) else { throw EtoileBasicErrors.whatTheFuck }
            let token = try keychain.string(forKey: "token")
            
            let configuration = JellyfinClient.Configuration(url: instance, client: "Etoile", deviceName: deviceName, deviceID: UUID().uuidString, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            let jellyfinClient = JellyfinClient(configuration: configuration, accessToken: token)
            self.client = jellyfinClient
        }
        
        try await reloadAlbumsFromFin()
        
        return (albums, songs)
    }
    
    // MARK: Playlists
    
    fileprivate func getSongsInPlaylistFromFin(playlistId: String) async throws -> [Song] {
        // Setup client
        if client == nil {
            let keychain = SimpleKeychain(service: "etoile")
            let instanceAsString = try keychain.string(forKey: "instance")
            guard let instance = URL(string: instanceAsString) else { throw EtoileBasicErrors.whatTheFuck }
            let token = try keychain.string(forKey: "token")
            
            let configuration = JellyfinClient.Configuration(url: instance, client: "Etoile", deviceName: "Temporary Etoile", deviceID: UUID().uuidString, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            let jellyfinClient = JellyfinClient(configuration: configuration, accessToken: token)
            self.client = jellyfinClient
        }
        
        
        // Send request
        let path = Paths.getItems(parameters: Paths.GetItemsParameters(parentID: playlistId))
        let response = try await client?.send(path)
        
        var songs: [Song] = []
        
        if response == nil {
            throw EtoileBasicErrors.whatTheFuck
        }
        
        // Gives the songs in the album
        for songItem in response?.value.items ?? [] {
            guard let name = songItem.name, let artist = songItem.albumArtist, let id = songItem.id else { continue }
            let image = await getArt(item: songItem)
            let song = Song(name: name, artist: artist, id: id, art: image, positionInAlbum: Int64(songItem.indexNumber ?? 0))
            songs.append(song)
        }
        
        if playlistsSongsStorage == nil {
            try setupCache()
        }
        
        try playlistsSongsStorage?.setObject(songs, forKey: playlistId)
        
        return songs
    }
    
    public func getSongsFromPlaylist(playlistId: String) async throws -> [Song] {
        if playlistsSongsStorage == nil {
            try setupCache()
        }
        
        if playlistsSongsStorage?.objectExists(forKey: playlistId) ?? false {
            if let songs = try playlistsSongsStorage?.object(forKey: playlistId) {
                return songs
            }
        }
        
        return try await getSongsInPlaylistFromFin(playlistId: playlistId)
        
    }
    
    /// Gets playlists from user's library
    private func getPlaylists() async throws -> [Playlist] {
        // Setup client
        if client == nil {
            let keychain = SimpleKeychain(service: "etoile")
            let instanceAsString = try keychain.string(forKey: "instance")
            guard let instance = URL(string: instanceAsString) else { throw EtoileBasicErrors.whatTheFuck }
            let token = try keychain.string(forKey: "token")
            
            let configuration = JellyfinClient.Configuration(url: instance, client: "Etoile", deviceName: "Temporary Etoile", deviceID: UUID().uuidString, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            let jellyfinClient = JellyfinClient(configuration: configuration, accessToken: token)
            self.client = jellyfinClient
        }
        
        var playlists: [Playlist] = []
        
        let path = Paths.getItems(parameters: Paths.GetItemsParameters(sortOrder: [.descending], includeItemTypes: [.playlistsFolder]))
        let response = try await client?.send(path)
        
        
        for item in response?.value.items ?? [] {
            
            
            if item.collectionType == .playlists {
                let playlistsPath = Paths.getItems(parameters:  Paths.GetItemsParameters(parentID: item.id))
                let playlistsResponse = try await client?.send(playlistsPath)
                
                for playlist1 in playlistsResponse?.value.items ?? [] {
                    
                    guard let name = playlist1.name, let id = playlist1.id else { continue }
                    
                    let image = await getArt(item: playlist1)
                    
                    let playlistTmp = Playlist(name: name, art: image, id: id)
                    
                    playlists.append(playlistTmp)
                    
                }
            }
            
        }
        
        if playlistsStorage == nil {
            try setupCache()
        }
        
        try playlistsStorage?.setObject(playlists, forKey: "playlists")
        
        return playlists
    }
    
    
    /// Reloads the playlists from cache
    public func reloadNoPullPlaylist() throws -> [Playlist]? {
        if playlistsStorage == nil {
            try setupCache()
        }
        
        var playlists: [Playlist] = []
        
        if playlistsStorage?.objectExists(forKey: "playlists") ?? false {
            playlists = try playlistsStorage?.object(forKey: "playlists") ?? []
        }
        
        return playlists
    }
    
    /// Pulls playlists from jellyfin
    public func pullPlaylistsFromFin() async throws -> [Playlist] {
        if playlistsStorage == nil {
            try setupCache()
        }
        
        return try await getPlaylists()
    }
    
    public func createPlaylist(name: String) async throws -> [Playlist] {
        // Setup client
        if client == nil {
            let keychain = SimpleKeychain(service: "etoile")
            let instanceAsString = try keychain.string(forKey: "instance")
            guard let instance = URL(string: instanceAsString) else { throw EtoileBasicErrors.whatTheFuck }
            let token = try keychain.string(forKey: "token")
            
            let configuration = JellyfinClient.Configuration(url: instance, client: "Etoile", deviceName: "Etoile temporary", deviceID: UUID().uuidString, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            let jellyfinClient = JellyfinClient(configuration: configuration, accessToken: token)
            self.client = jellyfinClient
        }
        
        if playlistsStorage == nil {
            try setupCache()
        }
        
        let path = Paths.createPlaylist(parameters: Paths.CreatePlaylistParameters(name: name))
        let response = try await client?.send(path)
        
        var playlists: [Playlist] = []
        
        if playlistsStorage?.objectExists(forKey: "playlists") ?? false {
            playlists = try playlistsStorage?.object(forKey: "playlists") ?? []
        }
        
        playlists.append(Playlist(name: name, id: response?.value.id ?? ""))
        
        try playlistsStorage?.setObject(playlists, forKey: "playlists")
        
        return playlists
    }
    
    public func addSongToPlaylist(playlist: Playlist, song: Song) async throws {
        // Setup client
        if client == nil {
            let keychain = SimpleKeychain(service: "etoile")
            let instanceAsString = try keychain.string(forKey: "instance")
            guard let instance = URL(string: instanceAsString) else { throw EtoileBasicErrors.whatTheFuck }
            let token = try keychain.string(forKey: "token")
            
            let configuration = JellyfinClient.Configuration(url: instance, client: "Etoile", deviceName: "Etoile temporary", deviceID: UUID().uuidString, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            let jellyfinClient = JellyfinClient(configuration: configuration, accessToken: token)
            self.client = jellyfinClient
        }
        
        if playlistsStorage == nil {
            try setupCache()
        }
        // Updating cache
        if playlistsSongsStorage?.objectExists(forKey: playlist.id) ?? false {
            if var songs = try playlistsSongsStorage?.object(forKey: playlist.id) {
                songs.append(song)
                try playlistsSongsStorage?.setObject(songs, forKey: playlist.id)
            }
        }
        
        // Telling remote
        var songs: [String] = []
        for song in try await getSongsFromPlaylist(playlistId: playlist.id) {
            songs.append(song.id)
        }
        songs.append(song.id)
        let update = UpdatePlaylistDto(ids: songs)
        let path = Paths.updatePlaylist(playlistID: playlist.id, update)
        let _ = try await client?.send(path)
        
    }
    
    public func removeSongFromPlaylist(playlistId: String, song: Song) async throws {
        // Setup client
        if client == nil {
            let keychain = SimpleKeychain(service: "etoile")
            let instanceAsString = try keychain.string(forKey: "instance")
            guard let instance = URL(string: instanceAsString) else { throw EtoileBasicErrors.whatTheFuck }
            let token = try keychain.string(forKey: "token")
            
            let configuration = JellyfinClient.Configuration(url: instance, client: "Etoile", deviceName: "Etoile temporary", deviceID: UUID().uuidString, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            let jellyfinClient = JellyfinClient(configuration: configuration, accessToken: token)
            self.client = jellyfinClient
        }
        
        if playlistsStorage == nil {
            try setupCache()
        }
        // Updating cache
        if playlistsSongsStorage?.objectExists(forKey: playlistId) ?? false {
            if var songs = try playlistsSongsStorage?.object(forKey: playlistId) {
                songs.removeAll(where: {$0.id == song.id})
                try playlistsSongsStorage?.setObject(songs, forKey: playlistId)
            }
        }
        let path = Paths.removeFromPlaylist(playlistID: playlistId, entryIDs: [song.id])
        let _ = try await client?.send(path)
        
        
    }
    
    public func deletePlaylist(playlist: Playlist) async throws {
        // Setup client
        if client == nil {
            let keychain = SimpleKeychain(service: "etoile")
            let instanceAsString = try keychain.string(forKey: "instance")
            guard let instance = URL(string: instanceAsString) else { throw EtoileBasicErrors.whatTheFuck }
            let token = try keychain.string(forKey: "token")
            
            let configuration = JellyfinClient.Configuration(url: instance, client: "Etoile", deviceName: "Etoile temporary", deviceID: UUID().uuidString, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            let jellyfinClient = JellyfinClient(configuration: configuration, accessToken: token)
            self.client = jellyfinClient
        }
        
        if playlistsStorage == nil {
            try setupCache()
        }
        // Updating cache
        if playlistsSongsStorage?.objectExists(forKey: playlist.id) ?? false {
            try playlistsSongsStorage?.removeObject(forKey: playlist.id)
        }
        
        if playlistsStorage?.objectExists(forKey: "playlists") ?? false {
            if var playlists = try playlistsStorage?.object(forKey: "playlists") {
                playlists.removeAll(where: {$0.id == playlist.id})
                try playlistsStorage?.setObject(playlists, forKey: "playlists")
            }
        }
        
        let path = Paths.deleteItem(itemID: playlist.id)
        let _ = try await client?.send(path)
        
    }
    public func logout() {
        print("Logout")
        let keychain = SimpleKeychain(service: "etoile")
        do {
            try keychain.deleteAll()
        } catch {
            print("logout failed for some reason!")
        }
    }
}
