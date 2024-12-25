//
//  Song+getLyrics.swift
//  EtoileKit
//
//  Created by Juliette Bernheisel on 8/31/24.
//

import Foundation
import JellyfinAPI
import SimpleKeychain

extension Song {
    
    /// Gets and returns the lyrics for the current song:)
    public func getLyrics(deviceName: String) async throws -> Lyrics {
        let keychain = SimpleKeychain(service: "etoile")
        let instanceAsString = try keychain.string(forKey: "instance")
        guard let instance = URL(string: instanceAsString) else { throw EtoileBasicErrors.whatTheFuck }
        let token = try keychain.string(forKey: "token")
        
        let configuration = JellyfinClient.Configuration(url: instance, client: "Etoile", deviceName: deviceName, deviceID: UUID().uuidString, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
        let jellyfinClient = JellyfinClient(configuration: configuration, accessToken: token)

        let lyricsPath = Paths.getLyrics(itemID: self.id)
        let lyrics = try await jellyfinClient.send(lyricsPath)
        var lines = lyrics.value.lyrics
        var offset = lyrics.value.metadata?.offset
        var synced = lyrics.value.metadata?.isSynced
        let toReturn = Lyrics(lines: lines, offset: offset, synced: synced)
        return toReturn
    }
}
