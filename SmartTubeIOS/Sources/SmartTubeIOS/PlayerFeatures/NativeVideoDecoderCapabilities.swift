import CoreMedia
import Darwin
import Foundation
import VideoToolbox

struct NativeVideoDecoderCapabilities: Sendable {
    let hardwareModel: String
    let osVersion: String
    let h264HardwareDecodeSupported: Bool
    let hevcHardwareDecodeSupported: Bool
    let vp9HardwareDecodeSupportedBeforeOptIn: Bool
    let vp9HardwareDecodeSupported: Bool
    let av1HardwareDecodeSupported: Bool
    let didRequestSupplementalVP9: Bool

    var summary: String {
        "AVC=\(h264HardwareDecodeSupported ? "yes" : "no") "
            + "HEVC=\(hevcHardwareDecodeSupported ? "yes" : "no") "
            + "VP9=\(vp9HardwareDecodeSupported ? "yes" : "no") "
            + "AV1=\(av1HardwareDecodeSupported ? "yes" : "no")"
    }

    static let current: Self = {
        let vp9BeforeSupplementalRequest = VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9)
        let didRequestSupplementalVP9: Bool
        if #available(iOS 26.2, tvOS 26.2, macOS 11.0, *) {
            VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
            didRequestSupplementalVP9 = true
        } else {
            didRequestSupplementalVP9 = false
        }

        return Self(
            hardwareModel: Self.machineModel(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            h264HardwareDecodeSupported: VTIsHardwareDecodeSupported(kCMVideoCodecType_H264),
            hevcHardwareDecodeSupported: VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC),
            vp9HardwareDecodeSupportedBeforeOptIn: vp9BeforeSupplementalRequest,
            vp9HardwareDecodeSupported: VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9),
            av1HardwareDecodeSupported: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1),
            didRequestSupplementalVP9: didRequestSupplementalVP9
        )
    }()

    private static func machineModel() -> String {
        let name = "hw.machine"
        var length = 0
        let sizeResult = name.withCString { pointer in
            sysctlbyname(pointer, nil, &length, nil, 0)
        }
        guard sizeResult == 0, length > 0 else { return "unknown" }

        var value = [UInt8](repeating: 0, count: length)
        let result = value.withUnsafeMutableBytes { buffer in
            name.withCString { pointer in
                sysctlbyname(pointer, buffer.baseAddress, &length, nil, 0)
            }
        }
        guard result == 0 else { return "unknown" }
        value = Array(value.prefix { $0 != 0 })
        return String(bytes: value, encoding: .utf8) ?? "unknown"
    }
}
