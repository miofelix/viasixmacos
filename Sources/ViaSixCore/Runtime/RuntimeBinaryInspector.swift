import Foundation

/// The small amount of Mach-O parsing needed to make sure a managed runtime
/// executable can run on this Mac.  We intentionally do not execute a newly
/// imported file just to inspect it: a header check is deterministic and does
/// not grant arbitrary code an opportunity to run during installation.
enum RuntimeBinaryInspection: Equatable, Sendable {
    /// A script with a shebang is architecture independent and can be used as
    /// a development/custom runtime executable.
    case script
    /// A Mach-O file containing one or more supported CPU architectures.
    case machO(Set<RuntimeArchitecture>)
    /// The file is not a valid executable format (or contains a truncated
    /// Mach-O/fat header).
    case invalid
}

enum RuntimeBinaryInspector {
    private static let machO32Big: UInt32 = 0xfeed_face
    private static let machO32Little: UInt32 = 0xcefa_edfe
    private static let machO64Big: UInt32 = 0xfeed_facf
    private static let machO64Little: UInt32 = 0xcffa_edfe
    private static let fat32Big: UInt32 = 0xcafe_babe
    private static let fat32Little: UInt32 = 0xbeba_feca
    private static let fat64Big: UInt32 = 0xcafe_babf
    private static let fat64Little: UInt32 = 0xbfba_feca

    // CPU_TYPE_* values from <mach/machine.h>.  Keeping the constants local
    // avoids making ViaSixCore depend on a platform-specific C module.
    private static let cpuTypeX8664: UInt32 = 0x0100_0007
    private static let cpuTypeArm64: UInt32 = 0x0100_000c

    static func inspect(fileAt url: URL) -> RuntimeBinaryInspection {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            return .invalid
        }

        guard data.count >= 2 else { return .invalid }
        if data[data.startIndex] == 0x23,
            data[data.startIndex + 1] == 0x21
        {
            return .script
        }

        guard data.count >= 4, let magic = readUInt32(data, at: 0, endian: .big) else {
            return .invalid
        }

        switch magic {
        case machO32Big, machO32Little:
            // ViaSix only supports 64-bit runtimes.  In particular, a
            // CPU_TYPE_*_64 value paired with a 32-bit header is malformed.
            return .invalid
        case machO64Big:
            return inspectThin(data, endian: .big, headerSize: 32)
        case machO64Little:
            return inspectThin(data, endian: .little, headerSize: 32)
        case fat32Big:
            return inspectFat(data, endian: .big, entrySize: 20, cpuOffset: 0)
        case fat32Little:
            return inspectFat(data, endian: .little, entrySize: 20, cpuOffset: 0)
        case fat64Big:
            return inspectFat(data, endian: .big, entrySize: 32, cpuOffset: 0)
        case fat64Little:
            return inspectFat(data, endian: .little, entrySize: 32, cpuOffset: 0)
        default:
            return .invalid
        }
    }

    private enum Endian {
        case big
        case little
    }

    private static func inspectThin(
        _ data: Data,
        endian: Endian,
        headerSize: Int
    ) -> RuntimeBinaryInspection {
        guard
            case .valid(let cpuType) = inspectMachOSlice(
                data,
                offset: 0,
                size: data.count,
                endian: endian,
                headerSize: headerSize
            ), let architecture = architecture(forCPUType: cpuType)
        else {
            return .invalid
        }
        return .machO([architecture])
    }

    private enum MachOSliceInspection {
        case valid(cpuType: UInt32)
        case invalid
    }

    private static func inspectMachOSlice(
        _ data: Data,
        offset: Int,
        size: Int,
        endian: Endian,
        headerSize: Int
    ) -> MachOSliceInspection {
        guard offset >= 0,
            size >= headerSize,
            offset <= data.count,
            size <= data.count - offset,
            let cpuType = readUInt32(data, at: offset + 4, endian: endian)
        else {
            return .invalid
        }
        return .valid(cpuType: cpuType)
    }

    private static func inspectFat(
        _ data: Data,
        endian: Endian,
        entrySize: Int,
        cpuOffset: Int
    ) -> RuntimeBinaryInspection {
        guard let count = readUInt32(data, at: 4, endian: endian),
            count > 0,
            count <= 64
        else {
            return .invalid
        }

        let countInt = Int(count)
        let entriesStart = 8
        guard countInt <= (data.count - entriesStart) / entrySize else {
            return .invalid
        }
        let entriesEnd = entriesStart + countInt * entrySize

        var architectures = Set<RuntimeArchitecture>()
        var slices: [(offset: Int, end: Int)] = []
        for index in 0..<countInt {
            let entryStart = entriesStart + index * entrySize
            guard let cpuType = readUInt32(data, at: entryStart + cpuOffset, endian: endian) else {
                return .invalid
            }

            let sliceOffset: UInt64
            let sliceSize: UInt64
            if entrySize == 20 {
                guard let offset32 = readUInt32(data, at: entryStart + 8, endian: endian),
                    let size32 = readUInt32(data, at: entryStart + 12, endian: endian)
                else {
                    return .invalid
                }
                sliceOffset = UInt64(offset32)
                sliceSize = UInt64(size32)
            } else {
                guard let offset64 = readUInt64(data, at: entryStart + 8, endian: endian),
                    let size64 = readUInt64(data, at: entryStart + 16, endian: endian)
                else {
                    return .invalid
                }
                sliceOffset = offset64
                sliceSize = size64
            }

            guard sliceOffset >= UInt64(entriesEnd),
                sliceSize >= 32,
                sliceOffset <= UInt64(data.count),
                sliceSize <= UInt64(data.count) - sliceOffset,
                let sliceOffsetInt = Int(exactly: sliceOffset),
                let sliceSizeInt = Int(exactly: sliceSize),
                let sliceMagic = readUInt32(data, at: sliceOffsetInt, endian: .big)
            else {
                return .invalid
            }

            let sliceEndian: Endian
            switch sliceMagic {
            case machO64Big:
                sliceEndian = .big
            case machO64Little:
                sliceEndian = .little
            default:
                // ViaSix only accepts 64-bit Mach-O payloads.  A fat table
                // that points at a truncated or non-Mach-O slice is invalid
                // even when another slice happens to be usable.
                return .invalid
            }
            guard
                case .valid(let sliceCPUType) = inspectMachOSlice(
                    data,
                    offset: sliceOffsetInt,
                    size: sliceSizeInt,
                    endian: sliceEndian,
                    headerSize: 32
                ), sliceCPUType == cpuType
            else {
                return .invalid
            }

            let sliceEnd = sliceOffsetInt + sliceSizeInt
            guard
                !slices.contains(where: { existing in
                    sliceOffsetInt < existing.end && existing.offset < sliceEnd
                })
            else {
                return .invalid
            }
            slices.append((offset: sliceOffsetInt, end: sliceEnd))

            if let architecture = architecture(forCPUType: cpuType) {
                architectures.insert(architecture)
            }
        }

        // A valid fat file containing only unsupported CPU types is still not
        // useful to ViaSix, so report it as invalid rather than accepting it.
        guard !architectures.isEmpty else { return .invalid }
        return .machO(architectures)
    }

    private static func architecture(forCPUType cpuType: UInt32) -> RuntimeArchitecture? {
        switch cpuType {
        case cpuTypeArm64: .arm64
        case cpuTypeX8664: .x8664
        default: nil
        }
    }

    private static func readUInt32(
        _ data: Data,
        at offset: Int,
        endian: Endian
    ) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        let bytes = data[offset..<(offset + 4)]
        switch endian {
        case .big:
            return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        case .little:
            return bytes.enumerated().reduce(UInt32(0)) {
                $0 | (UInt32($1.element) << (UInt32($1.offset) * 8))
            }
        }
    }

    private static func readUInt64(
        _ data: Data,
        at offset: Int,
        endian: Endian
    ) -> UInt64? {
        guard offset >= 0, offset <= data.count - 8 else { return nil }
        let bytes = data[offset..<(offset + 8)]
        switch endian {
        case .big:
            return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        case .little:
            return bytes.enumerated().reduce(UInt64(0)) {
                $0 | (UInt64($1.element) << (UInt64($1.offset) * 8))
            }
        }
    }
}
