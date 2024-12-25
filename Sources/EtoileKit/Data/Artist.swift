//
//  Artist.swift
//  EtoileKit
//
//  Created by Juliette Bernheisel on 8/30/24.
//

import Foundation

public struct Artist: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let image: Data?
}
