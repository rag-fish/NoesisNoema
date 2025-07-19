class Tokenizer {
    var type: String
    var version: String
    var vocab: Map
    var merges: List
    var modelFile: String
    var isEmbedded: Bool

    func encode(text: String) -> [Int] {
        // TODO: implement
    }
    func decode(tokens: [Int]) -> String {
        // TODO: implement
    }
    func loadFromFile(file: Any) -> Void {
        // TODO: implement
    }
}
