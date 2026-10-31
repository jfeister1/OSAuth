import Foundation

enum InformServiceError: LocalizedError {
    case missingIP
    case sshFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingIP:
            return "Device has no IP address for SSH set-inform."
        case .sshFailed(let message):
            return message
        }
    }
}

/// Points a factory-default UniFi device at the current controller via SSH `set-inform`.
struct InformService: Sendable {
    func setInform(
        on device: DiscoveredDevice,
        informURL: String,
        username: String,
        password: String
    ) async throws {
        guard let ip = device.ipAddress, !ip.isEmpty else {
            throw InformServiceError.missingIP
        }

        let port = device.sshPort ?? 22
        let remoteCommand = "set-inform \(informURL)"

        // Prefer sshpass-less expect-style via SSH_ASKPASS is fragile; use sshpass if present,
        // otherwise fall back to embedding credentials in an expect script via /usr/bin/ssh
        // with BatchMode disabled and a short helper.
        try await runSSH(
            host: ip,
            port: port,
            username: username,
            password: password,
            remoteCommand: remoteCommand
        )

        // Ubiquiti docs note set-inform often needs to be issued twice.
        try await Task.sleep(nanoseconds: 800_000_000)
        try await runSSH(
            host: ip,
            port: port,
            username: username,
            password: password,
            remoteCommand: remoteCommand
        )
    }

    private func runSSH(
        host: String,
        port: UInt16,
        username: String,
        password: String,
        remoteCommand: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.executeSSH(
                        host: host,
                        port: port,
                        username: username,
                        password: password,
                        remoteCommand: remoteCommand
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func executeSSH(
        host: String,
        port: UInt16,
        username: String,
        password: String,
        remoteCommand: String
    ) throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("UniFiJoin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let askPass = tempRoot.appendingPathComponent("askpass.sh")
        let escapedPassword = password
            .replacingOccurrences(of: "'", with: "'\\''")
        let askPassContents = """
            #!/bin/sh
            printf '%s\\n' '\(escapedPassword)'
            """
        try askPassContents.write(to: askPass, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askPass.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-p", "\(port)",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "PreferredAuthentications=password",
            "-o", "PubkeyAuthentication=no",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "ConnectTimeout=8",
            "\(username)@\(host)",
            remoteCommand
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["DISPLAY"] = environment["DISPLAY"] ?? ":0"
        environment["SSH_ASKPASS"] = askPass.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let combined = String(data: errData + outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = combined.isEmpty
                ? "SSH set-inform failed with exit \(process.terminationStatus)."
                : combined
            throw InformServiceError.sshFailed(message)
        }
    }
}
