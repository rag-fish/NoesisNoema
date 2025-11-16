// filepath: NoesisNoema/Shared/Utils/XCTestShim.swift
// Purpose: Workaround unresolved __swift_FORCE_LOAD_$_XCTestSwiftSupport when building app target with -enable-testing.
// This defines a no-op symbol only when XCTest is not available.

#if !canImport(XCTest)
@_cdecl("__swift_FORCE_LOAD_$_XCTestSwiftSupport")
public func __swift_FORCE_LOAD_$_XCTestSwiftSupport() { }

@_cdecl("__swift_FORCE_LOAD_$_XCTestSwiftSupport_$_NoesisNoema")
public func __swift_FORCE_LOAD_$_XCTestSwiftSupport_$NoesisNoema() { }

@_cdecl("__swift_FORCE_LOAD_$_XCTest_$_NoesisNoema")
public func __swift_FORCE_LOAD_$_XCTest_$NoesisNoema() { }
#endif
