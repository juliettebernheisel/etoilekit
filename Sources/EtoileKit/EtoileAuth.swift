//
//  EtoileAuth.swift
//  EtoileKit
//
//  Created by Daniel Cuevas on 12/26/24.
//

import SimpleKeychain
import OSLog

public class EtoileAuth {
    public init() {}
    /// Logs the user out
    public func logout()  {
        do {
            let keychain = SimpleKeychain(service: "etoile")
            try keychain.deleteItem(forKey: "token") // Remove the token
            try keychain.deleteItem(forKey: "instance") // Remove the instance
        } catch {
            Logger().error("Error logging out \(error)")
        }
    }
}
