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
    private var aggregate: [String: DiscoveredHost] = [:]

    public override init() { super.init() }

    public func start() throws {
        guard nwBrowser == nil, nsBrowser == nil else { throw BeamError.alreadyRunning }

        Task { @MainActor in
            self.aggregate.removeAll()
            self.hosts.removeAll()
        }

        // A) NWBrowser
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
                    if case let .service(name: svcName, type: _, domain: _, interface: _) = ep { name = svcName }
                    else { name = "Host" }
                    newAgg[ep.debugDescription] = DiscoveredHost(name: name, endpoint: ep)
                }
                self.aggregate = newAgg
                self.publishHosts()
                let names = newAgg.values.map { $0.name }.sorted().joined(separator: ", ")
                BeamLog.info("Browser results: \(names)", tag: "viewer")
            }
        }

        nw.start(queue: .main)

        // B) Classic NetServiceBrowser (for address logging + redundancy)
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

    @MainActor private func publishHosts() {
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
        service.resolve(withTimeout: 5.0)

        let name = service.name
        let type = service.type.hasSuffix(".") ? String(service.type.dropLast()) : service.type
        let domain = service.domain.isEmpty ? "local." : service.domain
        let ep = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        Task { @MainActor in
            self.aggregate[ep.debugDescription] = DiscoveredHost(name: name, endpoint: ep)
            if !moreComing { self.publishHosts() }
        }
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        BeamLog.warn("NSResolve error: \(errorDict) for \(sender.name)", tag: "viewer")
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        let addrs = (sender.addresses ?? []).compactMap { renderSockaddr($0) }
        if addrs.isEmpty {
            BeamLog.info("Resolved \(sender.name) (no addresses)", tag: "viewer")
        } else {
            BeamLog.info("Resolved \(sender.name) → \(addrs.joined(separator: ", "))", tag: "viewer")
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
