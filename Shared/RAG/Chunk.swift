// Project: NoesisNoema
// File: Chunk.swift
// Created by Раскольников on 2025/07/20.
// Description: Defines the Chunk class for handling text chunks with embeddings.
// License: MIT License


import Foundation

// Equatable: synthesized. All stored properties are Equatable, so Swift
// generates ==. Required so ExecutionResult (which now carries [Chunk] as
// citations, ADR-0008 R2) keeps its synthesized Equatable conformance.
// Adding the conformance is purely additive — no existing behavior changes.
struct Chunk: Codable, Equatable {
    var content: String
    var embedding: [Float]
    // metadata for citation popover
    var sourceTitle: String?
    var sourcePath: String?
    var page: Int?
}
