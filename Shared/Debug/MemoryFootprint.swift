//
//  MemoryFootprint.swift
//  NoesisNoema
//
//  Reads the jetsam-enforced physical memory footprint (TASK_VM_INFO
//  `phys_footprint`) — the exact value iOS uses when deciding which app to
//  kill under memory pressure. This is the number that matters for the n_ctx
//  ceiling question, NOT `resident_size` (which excludes some dirty/compressed
//  pages the jetsam accountant still charges to the app).
//
//  Pure Mach call, no allocation in the hot path — safe to poll every ~150ms
//  from the memory sampler.
//
//  License: MIT License
//

import Foundation

enum MemoryFootprint {

    /// Current `phys_footprint` in bytes, or nil if the Mach call fails.
    static func currentBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let kr: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    /// Current `phys_footprint` in MB (0 if unavailable).
    static func currentMB() -> Double {
        Double(currentBytes() ?? 0) / (1024.0 * 1024.0)
    }
}
