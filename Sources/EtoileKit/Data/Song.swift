//
//  Song.swift
//  etoile
//
//  Created by Juliette Bernheisel on 8/22/24.
//

import Foundation

public struct Song: Codable, Sendable, Identifiable, Equatable, Hashable {
    public init(name: String, artist: String, id: String, art: Data? = nil, positionInAlbum: Int64) {
        self.name = name
        self.artist = artist
        self.id = id
        self.art = art
        self.positionInAlbum = positionInAlbum
    }
    
    public let name: String
    public let artist: String
    public let id: String
    public let art: Data?
    public let positionInAlbum: Int64
}
