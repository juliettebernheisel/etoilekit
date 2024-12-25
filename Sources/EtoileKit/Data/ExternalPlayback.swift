//
//  ExternalPlayback.swift
//  EtoileKit
//
//  Created by Juliette Bernheisel on 9/3/24.
//


public struct ExternalPlayback: Codable, Sendable {
    public init(song: Song, deviceName: String) {
        self.song = song
        self.deviceName = deviceName
    }
    
    public let song: Song
    public let deviceName: String
}
