//
//  QAPair.swift
//  NoesisNoema
//
//  Created by Раскольников on 2025/08/03.
//

import Foundation

/// A structure representing a question and answer pair.
/// Conforms to Identifiable, Codable, and Equatable protocols.
struct QAPair: Identifiable, Codable, Equatable, Hashable {
    /// Unique identifier for the QAPair.
    let id: UUID
    /// The question string.
    var question: String
    /// The answer string.
    var answer: String
    /// Optional date timestamp for when the QAPair was created or modified.
    var date: Date?
    
    /// Initializes a new QAPair with given question, answer, and optional date.
    /// - Parameters:
    ///   - id: The unique identifier. Defaults to a new UUID.
    ///   - question: The question text.
    ///   - answer: The answer text.
    ///   - date: The optional timestamp. Defaults to current date.
    init(id: UUID = UUID(), question: String, answer: String, date: Date? = Date()) {
        self.id = id
        self.question = question
        self.answer = answer
        self.date = date
    }
}
