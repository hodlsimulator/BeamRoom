//
//  BeamTransportParameters.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//

import Network

enum BeamTransportParameters {

    /// Control channel over **infrastructure Wi-Fi only** (no AWDL/cellular).
    /// We rely on app heartbeats, but enabling kernel TCP keepalive adds resilience on some networks.
    static func tcpInfraWiFi() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        // Enable OS-level keepalive (short-ish; app heartbeats remain primary).
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 20       // seconds of idle before KA probes
        tcp.keepaliveInterval = 10   // seconds between KA probes
        tcp.keepaliveCount = 3       // probes before giving up

        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = false // exclude AWDL
        params.requiredInterfaceType = .wifi // infra Wi-Fi only
        params.prohibitedInterfaceTypes = [.cellular] // belt & braces
        return params
    }

    /// Keep this around for discovery or future P2P needs.
    static func tcpPeerToPeer() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true
        return params
    }
}
