//
//  BroadcastStatus.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Kept as a tiny standalone file because multiple targets import it.
//

import Foundation

public struct BroadcastStatus: Codable {
    public let on: Bool
    public init(on: Bool) { self.on = on }
}
