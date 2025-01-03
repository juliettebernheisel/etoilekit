//
//  Lyrics.swift
//  EtoileKit
//
//  Created by Juliette Bernheisel on 8/31/24.
//

import Foundation
import JellyfinAPI

public struct Lyrics {
    public let lines: [LyricLine]?
    public let offset: Int? // Has to be Int because JellyfinAPI package doesn't support Int64
    public let synced: Bool?
}
