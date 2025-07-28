// Project: NoesisNoema
// File: Tokenizer.swift
// Created by Раскольников on 2025/07/20.
// Description: Defines the Tokenizer class for handling text tokenization.
// License: MIT License

import Foundation

class Tokenizer {

    /**
        * Represents a tokenizer for text processing.
        * It includes properties for type, version, vocabulary, merges,
        * model file, and whether it is embedded.
        * It provides methods for encoding text into tokens and decoding tokens back into text.
     */
    var type: String
    
    /**
        * The version of the tokenizer.
        * This is used to ensure compatibility with the model and vocabulary.
     */
    var version: String
    
    /**
        * The vocabulary used by the tokenizer.
        * It maps tokens to their corresponding integer IDs.
        * This is essential for converting text into a format that can be processed by models.
        * The vocabulary is typically loaded from a file or defined in code.
     */
    var vocab: Dictionary<String, Int>
    
    /**
        * The merges used by the tokenizer.
        * This is a list of pairs of tokens that should be merged together.
        * It is used in subword tokenization to handle out-of-vocabulary words.
        */
    var merges: [String]
    
    /**
        * The file containing the model for the tokenizer.
        * This file is used to load the tokenizer's configuration and vocabulary.
        * It is typically a JSON or binary file that contains the necessary information for tokenization.
        */
    var modelFile: String
    
    /**
        * Indicates whether the tokenizer is embedded.
        * This is used to determine if the tokenizer can be used directly with models
        * or if it needs to be loaded from a file.
        */
    var isEmbedded: Bool

    /**
        * Initializes a Tokenizer with the specified properties.
        * - Parameter type: The type of the tokenizer (e.g., "BPE", "WordPiece").
        * - Parameter version: The version of the tokenizer.
        * - Parameter vocab: The vocabulary used by the tokenizer.
        * - Parameter merges: The merges used by the tokenizer.
        * - Parameter modelFile: The file containing the model for the tokenizer.
        * - Parameter isEmbedded: Indicates whether the tokenizer is embedded.
        */
    init(type: String, version: String, vocab: [String: Int], merges: [String], modelFile: String, isEmbedded: Bool = false) {
        self.type = type
        self.version = version
        self.vocab = vocab
        self.merges = merges
        self.modelFile = modelFile
        self.isEmbedded = isEmbedded
    }
    
    // デフォルト初期化子（最小限のデフォルト値で初期化）
    convenience init() {
        self.init(
            type: "BPE",
            version: "1.0",
            vocab: ["<unk>": -1, "hello": 1, "world": 2],
            merges: ["h e", "l l o", "w o r l d"],
            modelFile: "tokenizer_model.json",
            isEmbedded: true
        )
    }
     
    /**
        * Encodes the given text into a list of tokens.
        
        * - Parameter text: The text to be encoded.
        * - Returns: An array of integers representing the encoded tokens.
     */
    func encode(text: String) -> [Int] {
        // シンプルな空白区切り単語分割＋OOV対応
        let words = text.split(separator: " ").map { String($0) }
        return words.map { vocab[$0] ?? vocab["<unk>"] ?? -1 }
    }
    
    /**
        * Decodes the given list of tokens back into text.
        * - Parameter tokens: An array of integers representing the encoded tokens.
        * - Returns: A string containing the decoded text.
        */
    func decode(tokens: [Int]) -> String {
        // ID→単語の逆引き辞書を作成
        let id2word = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
        return tokens.map { id2word[$0] ?? "<unk>" }.joined(separator: " ")
    }
    
    /**
        * Loads the tokenizer from a file.
        * This method should read the tokenizer's configuration and vocabulary from the specified file.
        * - Parameter file: The file to load the tokenizer from.
        */
    func loadFromFile(file: Any) {
        // TODO: 実際のファイル読み込み実装
        print("Loading tokenizer from file: \(file)")
        // Placeholder for actual file loading logic
        // This could involve reading a JSON file or other formats to populate the tokenizer's properties
        // For now, we will just print a message
        // In a real implementation, you would parse the file and set the properties accordingly
        self.isEmbedded = true
        self.vocab = ["<unk>": -1, "hello": 1, "world": 2]
        self.merges = ["h e", "l l o", "w o r l d"]
        self.type = "BPE"
        self.version = "1.0"
        self.modelFile = "tokenizer_model.json"
        print("Tokenizer loaded with type: \(type), version: \(version), vocab size: \(vocab.count), merges count: \(merges.count), model file: \(modelFile), isEmbedded: \(isEmbedded)")
    }
}
