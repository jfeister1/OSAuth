import XCTest
@testable import UniFiJoin

final class DiscoveryParserTests: XCTestCase {
    func testParsesFactoryDefaultAnnouncement() throws {
        // version=2, cmd=0x06, length follows
        var payload = Data()
        payload.append(tlv(0x02, Data([0x80, 0x2a, 0xa8, 0x53, 0x43, 0x29, 192, 168, 1, 50])))
        payload.append(tlv(0x01, Data([0x80, 0x2a, 0xa8, 0x53, 0x43, 0x29])))
        payload.append(tlv(0x0b, Data("Lobby-AP".utf8)))
        payload.append(tlv(0x0c, Data("UAP-AC-Lite".utf8)))
        payload.append(tlv(0x15, Data("U7LT".utf8)))
        payload.append(tlv(0x16, Data("6.6.77".utf8)))
        payload.append(tlv(0x17, Data([0x01])))

        var packet = Data([0x02, 0x06])
        packet.append(UInt8((payload.count >> 8) & 0xff))
        packet.append(UInt8(payload.count & 0xff))
        packet.append(payload)

        let device = try XCTUnwrap(DiscoveryParser.parse(packet, sourceAddress: "192.168.1.50"))
        XCTAssertEqual(device.macAddress, "80:2a:a8:53:43:29")
        XCTAssertEqual(device.ipAddress, "192.168.1.50")
        XCTAssertEqual(device.hostname, "Lobby-AP")
        XCTAssertEqual(device.platform, "UAP-AC-Lite")
        XCTAssertEqual(device.model, "U7LT")
        XCTAssertEqual(device.firmware, "6.6.77")
        XCTAssertEqual(device.isFactoryDefault, true)
        XCTAssertTrue(device.isLikelyAdoptable)
    }

    func testRejectsTooShortPacket() {
        XCTAssertNil(DiscoveryParser.parse(Data([0x01, 0x00]), sourceAddress: "1.2.3.4"))
    }

    private func tlv(_ type: UInt8, _ value: Data) -> Data {
        var data = Data([type])
        data.append(UInt8((value.count >> 8) & 0xff))
        data.append(UInt8(value.count & 0xff))
        data.append(value)
        return data
    }
}
