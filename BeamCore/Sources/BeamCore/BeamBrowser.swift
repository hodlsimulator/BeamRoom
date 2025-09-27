//
//  BeamBrowser.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//

import Foundation
import Network
import OSLog

private let browserLog = Logger(subsystem: BeamConfig.subsystemViewer, category: "browser")

public final class BeamBrowser: NSObject, ObservableObject {
    @Published public private(set) var hosts: [DiscoveredHost] = []

    private var nwBrowser: NWBrowser?
    private var nsBrowser: NetServiceBrowser?
    private var nsServices: [NetService] = []

    /// Aggregate by service endpoint debugDescription
    private var aggregate: [String: DiscoveredHost] = [:]

    // Dedup helpers to avoid spam
    private var lastNamesLogged: String = ""
    private var resolveLogCache: [String: String] = [:] // serviceName -> "ip1, ip2"

    public override init() { super.init() }

    public func start() throws {
        guard nwBrowser == nil, nsBrowser == nil else { throw BeamError.alreadyRunning }
        Task { @MainActor in
            self.aggregate.removeAll()
            self.hosts.removeAll()
        }

        // A) NWBrowser (Network.framework Bonjour)
        let descriptor = NWBrowser.Descriptor.bonjour(type: BeamConfig.controlService, domain: nil)
        let params = BeamTransportParameters.tcpPeerToPeer()
        let nw = NWBrowser(for: descriptor, using: params)
        self.nwBrowser = nw

        BeamLog.info("Browser: start \(BeamConfig.controlService)", tag: "viewer")

        nw.stateUpdateHandler = { state in
            browserLog.debug("NWBrowser state: \(String(describing: state))")
            BeamLog.debug("Browser state=\(String(describing: state))", tag: "viewer")
            if case .failed(let err) = state {
                browserLog.error("NWBrowser failed: \(err.localizedDescription, privacy: .public)")
                BeamLog.error("Browser failed: \(err.localizedDescription)", tag: "viewer")
            }
        }

        nw.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            Task { @MainActor in
                var newAgg: [String: DiscoveredHost] = [:]
                for r in results {
                    let ep = r.endpoint
                    let name: String
                    if case let .service(name: svcName, type: _, domain: _, interface: _) = ep {
                        name = svcName
                    } else {
                        name = "Host"
                    }

                    var existing = self.aggregate[ep.debugDescription]
                    if existing == nil {
                        existing = DiscoveredHost(name: name, endpoint: ep)
                    }
                    newAgg[ep.debugDescription] = existing!
                }
                self.aggregate = newAgg
                self.publishHosts()

                let names = newAgg.values.map { $0.name }.sorted().joined(separator: ", ")
                // Dedup + DEBUG (no more INFO spam)
                if names != self.lastNamesLogged {
                    BeamLog.debug("Browser results: \(names)", tag: "viewer")
                    self.lastNamesLogged = names
                }
            }
        }

        nw.start(queue: .main)

        // B) Classic NetServiceBrowser (address resolution + redundancy)
        let nsb = NetServiceBrowser()
        nsb.includesPeerToPeer = true
        nsb.delegate = self
        self.nsBrowser = nsb

        let typeToSearch = BeamConfig.controlService.hasSuffix(".") ? BeamConfig.controlService : BeamConfig.controlService + "."
        nsb.searchForServices(ofType: typeToSearch, inDomain: "local.")
    }

    public func stop() {
        nwBrowser?.cancel(); nwBrowser = nil
        nsBrowser?.stop(); nsBrowser = nil
        for s in nsServices { s.stop() }
        nsServices.removeAll()
        Task { @MainActor in
            self.aggregate.removeAll()
            self.hosts.removeAll()
        }
        BeamLog.info("Browser: stopped", tag: "viewer")
    }

    @MainActor
    private func publishHosts() {
        var list = Array(aggregate.values)
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.hosts = list
    }
}

extension BeamBrowser: NetServiceBrowserDelegate, NetServiceDelegate {
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.includesPeerToPeer = true
        nsServices.append(service)
        service.resolve(withTimeout: 5.0) // addresses arrive in netServiceDidResolveAddress

        // Insert placeholder now; upgrade to IPv4 when resolved
        let name = service.name
        let type = service.type.hasSuffix(".") ? String(service.type.dropLast()) : service.type
        let domain = service.domain.isEmpty ? "local." : service.domain
        let ep = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        Task { @MainActor in
            if self.aggregate[ep.debugDescription] == nil {
                self.aggregate[ep.debugDescription] = DiscoveredHost(name: name, endpoint: ep)
                if !moreComing { self.publishHosts() }
            }
        }
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        BeamLog.warn("NSResolve error: \(errorDict) for \(sender.name)", tag: "viewer")
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        // Copy first to avoid capturing non-Sendable NetService
        let addresses = sender.addresses ?? []
        let name = sender.name
        let type = sender.type.hasSuffix(".") ? String(sender.type.dropLast()) : sender.type
        let domain = sender.domain.isEmpty ? "local." : sender.domain
        let serviceEP = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)

        let (preferred, ips) = choosePreferredEndpoint(from: addresses)
        let ipsJoined = ips.joined(separator: ", ")

        Task { @MainActor in
            var h = self.aggregate[serviceEP.debugDescription] ?? DiscoveredHost(name: name, endpoint: serviceEP)
            h.preferredEndpoint = preferred
            h.resolvedIPs = ips
            self.aggregate[serviceEP.debugDescription] = h
            self.publishHosts()

            // Dedup + DEBUG
            if self.resolveLogCache[name] != ipsJoined {
                BeamLog.debug("Resolved \(name) → \(ipsJoined)", tag: "viewer")
                self.resolveLogCache[name] = ipsJoined
            }
        }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let name = service.name
        let type = service.type.hasSuffix(".") ? String(service.type.dropLast()) : service.type
        let domain = service.domain.isEmpty ? "local." : service.domain
        let ep = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        Task { @MainActor in
            self.aggregate.removeValue(forKey: ep.debugDescription)
            if !moreComing { self.publishHosts() }
        }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        BeamLog.error("NSBrowser error: \(errorDict)", tag: "viewer")
    }
}
