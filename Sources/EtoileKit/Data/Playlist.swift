//
//  Playlist.swift
//  EtoileKit
//
//  Created by Juliette Bernheisel on 9/17/24.
//

import Foundation

public struct Playlist: Codable, Sendable, Identifiable, Equatable, Hashable  {
    public var name: String
    public var art: Data?
    public var id: String
}
