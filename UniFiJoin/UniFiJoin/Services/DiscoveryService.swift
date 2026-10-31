import Darwin
import Foundation

/// Discovers UniFi / Ubiquiti hardware via the UDP/10001 discovery protocol.
actor DiscoveryService {
    private let discoveryPort: UInt16 = 10001
    private let v1Probe = Data([0x01, 0x00, 0x00, 0x00])
    private let v2Probe = Data([0x02, 0x08, 0x00, 0x00])

    func scan(duration: TimeInterval = 2.5) async throws -> [DiscoveredDevice] {
        let port = discoveryPort
        let probes = [v1Probe, v2Probe]
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let devices = try Self.performScan(
                        duration: duration,
                        port: port,
                        probes: probes
                    )
                    continuation.resume(returning: devices)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func performScan(
        duration: TimeInterval,
        port: UInt16,
        probes: [Data]
    ) throws -> [DiscoveredDevice] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw DiscoveryError.socket(errno)
        }
        defer { close(fd) }

        var broadcastEnabled: Int32 = 1
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_BROADCAST,
            &broadcastEnabled,
            socklen_t(MemoryLayout.size(ofValue: broadcastEnabled))
        )

        var reuse: Int32 = 1
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout.size(ofValue: reuse))
        )
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_REUSEPORT,
            &reuse,
            socklen_t(MemoryLayout.size(ofValue: reuse))
        )

        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout.size(ofValue: timeout))
        )

        var bindAddress = sockaddr_in()
        bindAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddress.sin_family = sa_family_t(AF_INET)
        bindAddress.sin_port = port.bigEndian
        bindAddress.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &bindAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw DiscoveryError.bind(errno)
        }

        let destinations: [(String, in_addr_t)] = [
            ("255.255.255.255", inet_addr("255.255.255.255")),
            ("233.89.188.1", inet_addr("233.89.188.1"))
        ]

        for probe in probes {
            for destination in destinations {
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = port.bigEndian
                address.sin_addr = in_addr(s_addr: destination.1)

                _ = probe.withUnsafeBytes { buffer in
                    withUnsafePointer(to: &address) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(
                                fd,
                                buffer.baseAddress,
                                buffer.count,
                                0,
                                $0,
                                socklen_t(MemoryLayout<sockaddr_in>.size)
                            )
                        }
                    }
                }
            }
        }

        var discovered: [String: DiscoveredDevice] = [:]
        let deadline = Date().addingTimeInterval(duration)
        var buffer = [UInt8](repeating: 0, count: 8192)

        while Date() < deadline {
            var sender = sockaddr_in()
            var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &sender) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &senderLength)
                }
            }

            guard received > 0 else { continue }

            let data = Data(buffer.prefix(Int(received)))
            let source = String(cString: inet_ntoa(sender.sin_addr))
            if let device = DiscoveryParser.parse(data, sourceAddress: source) {
                discovered[device.id] = device
            }
        }

        return discovered.values.sorted {
            ($0.hostname ?? $0.macAddress)
                .localizedCaseInsensitiveCompare($1.hostname ?? $1.macAddress) == .orderedAscending
        }
    }
}

enum DiscoveryError: LocalizedError {
    case socket(Int32)
    case bind(Int32)

    var errorDescription: String? {
        switch self {
        case .socket(let code):
            return "Unable to open discovery socket (errno \(code))."
        case .bind(let code):
            return "Unable to bind UDP/10001 for discovery (errno \(code)). Another UniFi tool may be using the port."
        }
    }
}

enum DiscoveryParser {
    static func parse(_ data: Data, sourceAddress: String, now: Date = .now) -> DiscoveredDevice? {
        guard data.count >= 4 else { return nil }

        let version = data[data.startIndex]
        guard version == 0x01 || version == 0x02 else { return nil }

        let payloadLength = Int(data[data.startIndex + 2]) << 8 | Int(data[data.startIndex + 3])
        let payloadStart = data.startIndex + 4
        let payloadEnd = min(data.endIndex, payloadStart + payloadLength)
        guard payloadEnd > payloadStart else { return nil }

        var mac: String?
        var ip: String?
        var hostname: String?
        var platform: String?
        var model: String?
        var firmware: String?
        var isDefault: Bool?
        var uptime: UInt32?
        var sshPort: UInt16?

        var index = payloadStart
        while index + 3 <= payloadEnd {
            let type = data[index]
            let length = Int(data[index + 1]) << 8 | Int(data[index + 2])
            let valueStart = index + 3
            let valueEnd = valueStart + length
            guard valueEnd <= payloadEnd else { break }
            let value = data[valueStart..<valueEnd]

            switch type {
            case 0x01 where value.count == 6:
                mac = formatMAC(Data(value))
            case 0x02 where value.count >= 10:
                mac = mac ?? formatMAC(Data(value.prefix(6)))
                ip = ip ?? formatIPv4(Data(value.dropFirst(6).prefix(4)))
            case 0x03, 0x16:
                firmware = firmware ?? String(bytes: value, encoding: .utf8)
            case 0x0a where value.count == 4:
                uptime = UInt32(value[value.startIndex]) << 24
                    | UInt32(value[value.startIndex + 1]) << 16
                    | UInt32(value[value.startIndex + 2]) << 8
                    | UInt32(value[value.startIndex + 3])
            case 0x0b:
                hostname = String(bytes: value, encoding: .utf8)
            case 0x0c:
                platform = String(bytes: value, encoding: .utf8)
            case 0x14, 0x15:
                model = String(bytes: value, encoding: .utf8)
            case 0x17 where !value.isEmpty:
                isDefault = value[value.startIndex] != 0
            case 0x1c where value.count >= 1:
                if value.count == 2 {
                    sshPort = UInt16(value[value.startIndex]) << 8 | UInt16(value[value.startIndex + 1])
                } else {
                    sshPort = UInt16(value[value.startIndex])
                }
            default:
                break
            }

            index = valueEnd
        }

        guard let macAddress = mac else { return nil }

        return DiscoveredDevice(
            macAddress: macAddress,
            ipAddress: ip ?? (sourceAddress == "0.0.0.0" ? nil : sourceAddress),
            hostname: hostname?.trimmingCharacters(in: .whitespacesAndNewlines),
            platform: platform?.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model?.trimmingCharacters(in: .whitespacesAndNewlines),
            firmware: firmware?.trimmingCharacters(in: .whitespacesAndNewlines),
            isFactoryDefault: isDefault,
            uptimeSeconds: uptime,
            sshPort: sshPort,
            lastSeen: now,
            sourceAddress: sourceAddress
        )
    }

    private static func formatMAC(_ bytes: Data) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private static func formatIPv4(_ bytes: Data) -> String? {
        guard bytes.count == 4 else { return nil }
        return bytes.map(String.init).joined(separator: ".")
    }
}
