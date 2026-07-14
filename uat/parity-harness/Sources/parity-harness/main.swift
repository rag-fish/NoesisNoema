import Foundation
import llama

// Minimal pure-Swift embedding harness for xcframework/nomic parity UAT.
// Mirrors llama.cpp's examples/embedding/embedding.cpp single-prompt path
// (add_special=true, parse_special=true tokenization; all-token logits so
// the model's internal pooling sees every position; llama_get_embeddings_seq
// for the pooled output) so results are directly comparable to a reference
// llama-server run of the same GGUF at the same llama.cpp commit.

struct Input: Decodable {
    let id: String
    let prefix: String
    let text: String
}

struct Output: Encodable {
    let id: String
    let embedding: [Float]
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else {
    fail("usage: parity-harness <model.gguf> <inputs.json>")
}
let modelPath = args[1]
let inputsPath = args[2]

guard let inputsData = FileManager.default.contents(atPath: inputsPath) else {
    fail("cannot read inputs file: \(inputsPath)")
}
let inputs = try! JSONDecoder().decode([Input].self, from: inputsData)

llama_backend_init()
defer { llama_backend_free() }

var modelParams = llama_model_default_params()
guard let model = llama_model_load_from_file(modelPath, modelParams) else {
    fail("failed to load model at \(modelPath)")
}
defer { llama_model_free(model) }

let vocab = llama_model_get_vocab(model)

var ctxParams = llama_context_default_params()
ctxParams.n_ctx = 512
ctxParams.n_batch = 512
ctxParams.n_ubatch = 512
ctxParams.embeddings = true
// pooling_type left at llama_context_default_params()'s default
// (LLAMA_POOLING_TYPE_UNSPECIFIED), i.e. deferred to the model's own
// GGUF-declared pooling — same as a llama-server run with no --pooling flag.

guard let ctx = llama_init_from_model(model, ctxParams) else {
    fail("failed to create context")
}
defer { llama_free(ctx) }

let nEmbd = Int(llama_model_n_embd_out(model))
let poolingType = llama_pooling_type(ctx)
guard poolingType != LLAMA_POOLING_TYPE_NONE else {
    fail("model pooling_type is NONE; this harness only supports pooled (sequence) embeddings")
}

func tokenize(_ text: String) -> [llama_token] {
    let utf8Count = text.utf8.count
    let capacity = utf8Count + 8
    var tokens = [llama_token](repeating: 0, count: capacity)
    let n = text.withCString { cstr -> Int32 in
        tokens.withUnsafeMutableBufferPointer { buf in
            llama_tokenize(vocab, cstr, Int32(utf8Count), buf.baseAddress, Int32(capacity), true, true)
        }
    }
    guard n >= 0 else { fail("tokenize: buffer too small (needed \(-n))") }
    return Array(tokens[0..<Int(n)])
}

func embed(text: String, prefix: String) -> [Float] {
    let tokens = tokenize(prefix + text)

    var batch = llama_batch_init(Int32(max(tokens.count, 1)), 0, 1)
    defer { llama_batch_free(batch) }

    for (i, tok) in tokens.enumerated() {
        let idx = Int(batch.n_tokens)
        batch.token[idx] = tok
        batch.pos[idx] = Int32(i)
        batch.n_seq_id[idx] = 1
        batch.seq_id[idx]![0] = 0
        batch.logits[idx] = 1 // mark every position so internal pooling sees the full sequence
        batch.n_tokens += 1
    }

    llama_memory_clear(llama_get_memory(ctx), true)
    guard llama_decode(ctx, batch) >= 0 else {
        fail("llama_decode failed for text: \(text.prefix(40))...")
    }

    guard let embdPtr = llama_get_embeddings_seq(ctx, 0) else {
        fail("llama_get_embeddings_seq returned NULL")
    }
    return Array(UnsafeBufferPointer(start: embdPtr, count: nEmbd))
}

var outputs: [Output] = []
for input in inputs {
    let vec = embed(text: input.text, prefix: input.prefix)
    outputs.append(Output(id: input.id, embedding: vec))
}

let encoder = JSONEncoder()
let outData = try! encoder.encode(outputs)
FileHandle.standardOutput.write(outData)
