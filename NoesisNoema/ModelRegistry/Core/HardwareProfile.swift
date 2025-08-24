// Project: NoesisNoema
// File: HardwareProfile.swift
// Description: Hardware profiling for Darwin/arm64 and Linux/x86_64

import Foundation
#if !os(Linux)
import Darwin
#endif

struct HardwareProfile: Codable, Sendable {
    let os: String
    let arch: String
    let cpuCores: Int
    let memTotalGB: Double
    let vramTotalGB: Double
    let gpuVendor: String?
    let soc: String?
}

enum HardwareProbe {
    static func probe() -> HardwareProfile {
        #if os(Linux)
        return probeLinux()
        #else
        return probeDarwin()
        #endif
    }

    #if os(Linux)
    private static func probeLinux() -> HardwareProfile {
        let cores = ProcessInfo.processInfo.processorCount
        // MemTotal from /proc/meminfo in kB
        var memTotalGB: Double = 0
        if let content = try? String(contentsOfFile: "/proc/meminfo", encoding: .utf8) {
            if let line = content.split(separator: "\n").first(where: { $0.hasPrefix("MemTotal:") }) {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if parts.count >= 2, let kB = Double(parts[1]) {
                    memTotalGB = (kB / 1024.0 / 1024.0).rounded(toPlaces: 2)
                }
            }
        }
        // VRAM best-effort (AMD)
        var vramGB: Double = 0
        if let vramStr = try? String(contentsOfFile: "/sys/class/drm/card0/device/mem_info_vram_total", encoding: .utf8),
           let bytes = Double(vramStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            vramGB = (bytes / 1024.0 / 1024.0 / 1024.0).rounded(toPlaces: 2)
        }
        return HardwareProfile(os: "Linux", arch: platformMachine(), cpuCores: cores, memTotalGB: memTotalGB, vramTotalGB: vramGB, gpuVendor: nil, soc: nil)
    }
    #endif

    #if !os(Linux)
    private static func probeDarwin() -> HardwareProfile {
        let cores = ProcessInfo.processInfo.processorCount
        let memBytes = ProcessInfo.processInfo.physicalMemory
        let memGB = (Double(memBytes) / 1073741824.0).rounded(toPlaces: 2)
        // Apple Silicon uses unified memory: use total memory as VRAM budget
        #if arch(arm64)
        let vramGB = memGB
        let vendor = "Apple"
        let chip = sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.model")
        return HardwareProfile(os: "Darwin", arch: "arm64", cpuCores: cores, memTotalGB: memGB, vramTotalGB: vramGB, gpuVendor: vendor, soc: chip)
        #else
        // Intel mac fallback
        let vramGB = 0.0
        return HardwareProfile(os: "Darwin", arch: platformMachine(), cpuCores: cores, memTotalGB: memGB, vramTotalGB: vramGB, gpuVendor: nil, soc: nil)
        #endif
    }
    #endif

    private static func platformMachine() -> String {
        #if os(Linux)
        return (try? String(contentsOfFile: "/proc/cpuinfo")).flatMap { _ in "x86_64" } ?? "unknown"
        #else
        return "arm64"
        #endif
    }

    private static func sysctlString(_ name: String) -> String? {
        var size: size_t = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        let result = sysctlbyname(name, &buffer, &size, nil, 0)
        if result == 0 {
            return String(cString: buffer)
        }
        return nil
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}
