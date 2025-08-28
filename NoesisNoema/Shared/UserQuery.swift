// NoesisNoema is a knowledge graph framework for building AI applications.
// It provides a way to query and manage knowledge graphs using natural language.
// This file defines the UserQuery class for handling user queries.
// Created by NoesisNoema on 2024-02-24.
// License: MIT License
// Project: NoesisNoema

import Foundation

// UserQuery.swift
/**
    Represents a user query in the NoesisNoema framework.
    This class is designed to hold the user's question.
    Note: The retrieval-augmented generation (RAG) logic and processing
    of the query are handled externally by a service or controller.
*/
class UserQuery {

    /**
        The question asked by the user.
    */
    var question: String

    /**
        Initializes a UserQuery with the specified question.
        - Parameter question: The question to be asked by the user.
        - Note: This initializer sets the question property of the UserQuery instance.
        - Example:
        ```swift
        let userQuery = UserQuery(question: "What is the capital of France?")
        print(userQuery.question) // Prints "What is the capital of France?"
        ```
     */
    init(question: String) {
        self.question = question
    }

}
