//
//  Transport.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//

import Foundation

public enum BeamRole: String { case host, viewer }

public struct BeamVersion {
    public static let string = "0.1.0-M0"
}

public protocol BeamIdentifiable { var id: UUID { get } }

public protocol BeamControlChannel {
    func start() async throws
    func stop() async
}

public protocol BeamMediaChannel {
    func start() async throws
    func stop() async
}
