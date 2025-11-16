// Project: NoesisNoema
// File: Chunk.swift
// Created by Раскольников on 2025/07/20.
// Description: Defines the Chunk class for handling text chunks with embeddings.
// License: MIT License


import Foundation

struct Chunk: Codable {
    var content: String
    var embedding: [Float]
    // metadata for citation popover
    var sourceTitle: String?
    var sourcePath: String?
    var page: Int?
}
