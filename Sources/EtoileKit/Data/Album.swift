//
//  Album.swift
//  EtoileKit
//
//  Created by Juliette Bernheisel on 8/30/24.
//

import Foundation

public struct Album: Codable, Sendable, Identifiable, Equatable, Hashable {
    public init(name: String, artist: String, art: Data?, id: String) {
        self.name = name
        self.artist = artist
        self.art = art
        self.id = id
    }
    
    public let name: String
    public let artist: String
    public let art: Data?
    public let id: String
}
