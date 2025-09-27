//
//  BeamTransportParameters.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//

import Network

enum BeamTransportParameters {
    /// TCP with peer-to-peer enabled. We rely on app-level heartbeats, so we do **not**
    /// enable kernel keepalives (aggressive KA on iOS can cause spurious RSTs).
    static func tcpPeerToPeer() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        // If you ever want kernel keepalive, keep it conservative (example):
        // tcp.enableKeepalive = true
        // tcp.keepaliveIdle = 120
        // tcp.keepaliveInterval = 30
        // tcp.keepaliveCount = 4

        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true // AWDL / Wi-Fi Aware allowed
        return params
    }
}
