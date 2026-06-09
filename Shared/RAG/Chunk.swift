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

    // ADR-0011 PR-B: optional citation metadata sourced from a v1.2 RAGpack's
    // citations.jsonl. All optional and defaulted — purely additive, so every
    // existing constructor (`Chunk(content:embedding:)` etc.) keeps compiling and
    // existing encoded chunks keep decoding.
    var docId: String?
    var charStart: Int?
    var charEnd: Int?
    var paragraphBoundaries: [Int]?

    enum CodingKeys: String, CodingKey {
        case content, embedding, sourceTitle, sourcePath, page
        case docId, charStart, charEnd, paragraphBoundaries
    }

    init(content: String,
         embedding: [Float],
         sourceTitle: String? = nil,
         sourcePath: String? = nil,
         page: Int? = nil,
         docId: String? = nil,
         charStart: Int? = nil,
         charEnd: Int? = nil,
         paragraphBoundaries: [Int]? = nil) {
        self.content = content
        self.embedding = embedding
        self.sourceTitle = sourceTitle
        self.sourcePath = sourcePath
        self.page = page
        self.docId = docId
        self.charStart = charStart
        self.charEnd = charEnd
        self.paragraphBoundaries = paragraphBoundaries
    }

    // Custom decoder so a v1.2 chunks.json that carries content (+ optional
    // metadata) but NO embedding still decodes — the embedding is filled from
    // embeddings.npy by RAGpackReader. Previously-encoded chunks (embedding
    // present) continue to decode unchanged. Encoding stays synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.content = try c.decode(String.self, forKey: .content)
        self.embedding = try c.decodeIfPresent([Float].self, forKey: .embedding) ?? []
        self.sourceTitle = try c.decodeIfPresent(String.self, forKey: .sourceTitle)
        self.sourcePath = try c.decodeIfPresent(String.self, forKey: .sourcePath)
        self.page = try c.decodeIfPresent(Int.self, forKey: .page)
        self.docId = try c.decodeIfPresent(String.self, forKey: .docId)
        self.charStart = try c.decodeIfPresent(Int.self, forKey: .charStart)
        self.charEnd = try c.decodeIfPresent(Int.self, forKey: .charEnd)
        self.paragraphBoundaries = try c.decodeIfPresent([Int].self, forKey: .paragraphBoundaries)
    }
}
