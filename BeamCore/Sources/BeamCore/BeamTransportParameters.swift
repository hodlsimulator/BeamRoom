//
//  BeamTransportParameters.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//

import Network

enum BeamTransportParameters {
    /// Control channel over local Wi‑Fi / peer‑to‑peer (no cellular).
    /// Uses OS TCP keepalive in addition to app heartbeats for resilience.
    static func tcpInfraWiFi() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        // Enable OS-level keepalive (short-ish; app heartbeats remain primary).
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 20       // seconds of idle before KA probes
        tcp.keepaliveInterval = 10   // seconds between KA probes
        tcp.keepaliveCount = 3       // probes before giving up

        let params = NWParameters(tls: nil, tcp: tcp)

        // Allow both infrastructure Wi‑Fi and peer‑to‑peer (AWDL / Wi‑Fi Aware).
        params.includePeerToPeer = true

        // Avoid cellular; BeamRoom is local-only.
        params.prohibitedInterfaceTypes = [.cellular]

        return params
    }

    /// Peer‑to‑peer oriented parameters (used for discovery via NWBrowser, etc).
    static func tcpPeerToPeer() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true
        return params
    }
}
