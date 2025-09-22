//
//  BeamTransportParameters.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//

import Network

enum BeamTransportParameters {
    /// TCP with peer-to-peer enabled and TCP keepalives configured.
    static func tcpPeerToPeer() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        // tcp.keepaliveCount = 3 // optional

        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true // AWDL / Wi-Fi Aware
        return params
    }
}
