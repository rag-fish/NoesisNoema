// EDIT POLICY:
// - Only update this file to adapt to upstream llama.cpp C API changes or add thin shims.
// - Do NOT call llama_* from other files directly; route via LlamaState and this shim.
// - If upstream changes break the build, fix here and add/adjust a unit test.

import Foundation

#if !DISABLE_LLAMA
import llama
#endif

enum LlamaError: Error {
    case couldNotInitializeContext
    case initFailed(reason: String)
    case tokenizeFailed(reason: String)
    case noResponse(reason: String)
    case unsupportedArchitecture(arch: String)
}

#if !DISABLE_LLAMA

func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

func llama_batch_add(_ batch: inout llama_batch, _ id: llama_token, _ pos: llama_pos, _ seq_ids: [llama_seq_id], _ logits: Bool) {
    batch.token   [Int(batch.n_tokens)] = id
    batch.pos     [Int(batch.n_tokens)] = pos
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
    for i in 0..<seq_ids.count {
        batch.seq_id[Int(batch.n_tokens)]![Int(i)] = seq_ids[i]
    }
    batch.logits  [Int(batch.n_tokens)] = logits ? 1 : 0

    batch.n_tokens += 1
}

actor LlamaContext {
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var vocab: OpaquePointer
    private var sampling: UnsafeMutablePointer<llama_sampler>
    private var batch: llama_batch
    private var tokens_list: [llama_token]
    var is_done: Bool = false

    // verbose logging switch
    private var verbose: Bool = false
    private func dprint(_ items: Any...) {
        if verbose {
            let line = items.map { String(describing: $0) }.joined(separator: " ")
            print(line)
        }
    }

    /// This variable is used to store temporarily invalid cchars
    private var temporary_invalid_cchars: [CChar]

    var n_len: Int32 = 1024
    var n_cur: Int32 = 0

    var n_decode: Int32 = 0

    init(model: OpaquePointer, context: OpaquePointer, initialNLen: Int32 = 1024) {
        self.model = model
        self.context = context
        self.tokens_list = []
        self.batch = llama_batch_init(512, 0, 1)
        self.temporary_invalid_cchars = []
        let sparams = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_temp(0.4))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dist(1234))
        vocab = llama_model_get_vocab(model)
        self.n_len = initialNLen
    }

    deinit {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_model_free(model)
        llama_free(context)
        llama_backend_free()
    }

    static func create_context(path: String) throws -> LlamaContext {
        #if DEBUG
        print("🧩 [LibLlama] GGUF path: \(path)")
        #endif
        SystemLog().logEvent(event: "[LibLlama] Loading GGUF from: \(path)")

        // iOSではMetalを無効化してCPUフォールバック（MTLCompiler内部エラー対策）
        #if os(iOS)
        setenv("LLAMA_NO_METAL", "1", 1)
        #endif
        #if targetEnvironment(simulator)
        setenv("LLAMA_NO_METAL", "1", 1)
        #endif

        llama_backend_init()
        #if DEBUG
        print("✅ [LibLlama] llama_backend_init() complete")
        #endif

        var model_params = llama_model_default_params()

        #if targetEnvironment(simulator)
        model_params.n_gpu_layers = 0
        print("Running on iOS simulator, forcing CPU (n_gpu_layers = 0, LLAMA_NO_METAL=1)")
        #endif
        #if os(iOS)
        model_params.n_gpu_layers = 0
        print("Running on iOS device, forcing CPU (n_gpu_layers = 0, LLAMA_NO_METAL=1)")
        #endif

        #if DEBUG
        print("📦 [LibLlama] Loading model with n_gpu_layers=\(model_params.n_gpu_layers)...")
        #endif

        let model = llama_model_load_from_file(path, model_params)
        guard let model else {
            let errorMsg = "Could not load model at \(path)"
            #if DEBUG
            print("❌ [LibLlama] \(errorMsg)")
            #endif
            SystemLog().logEvent(event: "[LibLlama] ERROR: \(errorMsg)")
            throw LlamaError.initFailed(reason: errorMsg)
        }

        #if DEBUG
        print("✅ [LibLlama] Model loaded successfully")
        #endif

        // Get and validate GGUF metadata
        let modelDesc = UnsafeMutablePointer<Int8>.allocate(capacity: 512)
        modelDesc.initialize(repeating: Int8(0), count: 512)
        defer { modelDesc.deallocate() }

        let nChars = llama_model_desc(model, modelDesc, 512)
        let modelInfo = String(cString: modelDesc)

        #if DEBUG
        print("📦 [LibLlama] Model info: \(modelInfo)")
        #endif
        SystemLog().logEvent(event: "[LibLlama] Model desc: \(modelInfo)")

        #if os(iOS)
        let n_threads = max(1, min(4, ProcessInfo.processInfo.processorCount))
        #else
        let n_threads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        #endif

        #if DEBUG
        print("⚙️ [LibLlama] Using \(n_threads) threads")
        #endif
        SystemLog().logEvent(event: "[LibLlama] Config: threads=\(n_threads)")

        // 修正箇所：Never型 → 実際の構造体に置換
        var ctx_params = llama_context_default_params()

        #if os(iOS) || targetEnvironment(simulator)
        ctx_params.n_ctx = 1024
        #else
        ctx_params.n_ctx = 2048
        #endif
        ctx_params.n_threads       = Int32(n_threads)
        ctx_params.n_threads_batch = Int32(n_threads)

        #if DEBUG
        print("📦 [LibLlama] Creating context with n_ctx=\(ctx_params.n_ctx)...")
        #endif

        let context = llama_init_from_model(model, ctx_params)
        guard let context else {
            let errorMsg = "Could not initialize context from model"
            #if DEBUG
            print("❌ [LibLlama] \(errorMsg)")
            #endif
            SystemLog().logEvent(event: "[LibLlama] ERROR: \(errorMsg)")
            throw LlamaError.initFailed(reason: errorMsg)
        }

        #if DEBUG
        print("✅ [LibLlama] Context initialized successfully (ctx != nil)")
        #endif
        SystemLog().logEvent(event: "[LibLlama] Context created: n_ctx=\(ctx_params.n_ctx)")

        #if os(iOS)
        return LlamaContext(model: model, context: context, initialNLen: 256)
        #else
        return LlamaContext(model: model, context: context)
        #endif
    }

    func model_info() -> String {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        result.initialize(repeating: Int8(0), count: 256)
        defer {
            result.deallocate()
        }

        // TODO: this is probably very stupid way to get the string from C

        let nChars = llama_model_desc(model, result, 256)
        let bufferPointer = UnsafeBufferPointer(start: result, count: Int(nChars))

        var SwiftString = ""
        for char in bufferPointer {
            SwiftString.append(Character(UnicodeScalar(UInt8(char))))
        }

        return SwiftString
    }

    /// Exposes llama_print_system_info() as a Swift String for logging.
    func system_info() -> String {
        guard let cstr = llama_print_system_info() else { return "" }
        return String(cString: cstr)
    }

    /// Test function: call llama_print_system_info and return safely
    func printSystemInfo() -> String {
        #if DEBUG
        print("🧪 [LibLlama] Testing llama_print_system_info() call...")
        #endif
        let info = system_info()
        #if DEBUG
        print("✅ [LibLlama] System info retrieved: \(info)")
        #endif
        return info
    }

    // MARK: - Verbosity
    func set_verbose(_ on: Bool) {
        self.verbose = on
    }

    // MARK: - Sampling configuration
    /// Rebuild sampler chain with given parameters (simplified to match reference)
    func configure_sampling(temp: Float, top_k: Int32 = 0, top_p: Float = 0.0, seed: UInt64 = 1234) {
        llama_sampler_free(self.sampling)
        let sparams = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_temp(temp))
        if top_k > 0 {
            llama_sampler_chain_add(self.sampling, llama_sampler_init_top_k(top_k))
        }
        if top_p > 0.0 {
            llama_sampler_chain_add(self.sampling, llama_sampler_init_top_p(top_p, 1))
        }
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dist(UInt32(seed)))
    }

    func set_n_len(_ value: Int32) {
        self.n_len = value
    }

    func get_n_tokens() -> Int32 {
        return batch.n_tokens;
    }

    func completion_init(text: String) {
        dprint("attempting to complete \"\(text)\"")

        #if DEBUG
        print("🚀 [LibLlama] completion_init: prompt length \(text.count) chars")
        #endif
        SystemLog().logEvent(event: "[LibLlama] completion_init: promptLen=\(text.count)")

        tokens_list = tokenize(text: text, add_bos: true)
        temporary_invalid_cchars = []

        #if DEBUG
        print("🔤 [LibLlama] Tokenized to \(tokens_list.count) tokens")
        #endif

        // CRITICAL FIX 1: Clear KV cache before starting new generation
        #if DEBUG
        print("🧹 [LibLlama] Clearing KV cache before decode...")
        #endif
        llama_memory_clear(llama_get_memory(context), false)

        let n_ctx = llama_n_ctx(context)
        let n_kv_req = tokens_list.count + (Int(n_len) - tokens_list.count)

        dprint("\n n_len = \(n_len), n_ctx = \(n_ctx), n_kv_req = \(n_kv_req)")

        #if DEBUG
        print("📊 [LibLlama] Batch config: n_len=\(n_len), n_ctx=\(n_ctx), n_kv_req=\(n_kv_req)")
        print("📍 [LibLlama] Context pointer: \(String(describing: context))")
        #endif

        if n_kv_req > n_ctx {
            let warning = "error: n_kv_req > n_ctx, the required KV cache size is not big enough"
            print(warning)
            #if DEBUG
            print("⚠️ [LibLlama] \(warning)")
            #endif
            SystemLog().logEvent(event: "[LibLlama] \(warning)")
        }

        for id in tokens_list {
            dprint(String(cString: token_to_piece(token: id) + [0]))
        }

        // CRITICAL FIX 2: Reinitialize batch for each decode cycle
        #if DEBUG
        print("🔄 [LibLlama] Reinitializing batch...")
        #endif
        llama_batch_free(batch)
        batch = llama_batch_init(512, 0, 1)

        #if DEBUG
        print("✅ [LibLlama] Batch reinitialized with capacity 512")
        #endif

        llama_batch_clear(&batch)

        // CRITICAL FIX 3: Validate token positions are consecutive
        for i1 in 0..<tokens_list.count {
            let i = Int(i1)
            llama_batch_add(&batch, tokens_list[i], Int32(i), [0], false)
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1

        #if DEBUG
        print("🔢 [LibLlama] Batch state before decode:")
        print("   - n_tokens: \(batch.n_tokens)")
        print("   - positions: 0..\(batch.n_tokens - 1)")
        print("   - all sequences: [0]")
        #endif

        // CRITICAL FIX 4: Assert batch is valid before decode
        guard batch.n_tokens > 0 else {
            #if DEBUG
            print("❌ [LibLlama] ERROR: batch.n_tokens is 0, aborting decode")
            #endif
            SystemLog().logEvent(event: "[LibLlama] ERROR: Empty batch")
            is_done = true
            return
        }

        #if DEBUG
        print("🚀 [LibLlama] Starting decode with \(batch.n_tokens) prompt tokens...")
        #endif

        if llama_decode(context, batch) != 0 {
            let error = "llama_decode() failed"
            print(error)
            #if DEBUG
            print("❌ [LibLlama] \(error)")
            print("   - batch.n_tokens: \(batch.n_tokens)")
            print("   - context: \(String(describing: context))")
            #endif
            SystemLog().logEvent(event: "[LibLlama] ERROR: \(error)")
        } else {
            #if DEBUG
            print("✅ [LibLlama] Initial decode successful")
            #endif
        }

        n_cur = batch.n_tokens
        n_decode = 0
        is_done = false

        #if DEBUG
        print("✅ [LibLlama] completion_init complete, n_cur=\(n_cur)")
        #endif
        SystemLog().logEvent(event: "[LibLlama] Prompt processed: \(tokens_list.count) tokens")
    }

    func completion_loop() -> String {
        var new_token_id: llama_token = 0

        // CRITICAL FIX 5: Validate context and batch before sampling
        guard batch.n_tokens > 0 else {
            #if DEBUG
            print("❌ [LibLlama] ERROR: batch.n_tokens is 0 in completion_loop")
            #endif
            is_done = true
            return ""
        }

        #if DEBUG
        if n_decode == 0 {
            print("🎲 [LibLlama] About to sample first token...")
            print("   - context: \(String(describing: context))")
            print("   - batch.n_tokens: \(batch.n_tokens)")
            print("   - sampling index: \(batch.n_tokens - 1)")
        }
        #endif

        new_token_id = llama_sampler_sample(sampling, context, batch.n_tokens - 1)

        dprint("[DEBUG] new_token_id:", new_token_id)
        dprint("[DEBUG] is_eog:", llama_vocab_is_eog(vocab, new_token_id), "n_cur:", n_cur, "n_len:", n_len)

        #if DEBUG
        if n_decode == 0 {
            print("🔹 [LibLlama] First token sampled: id=\(new_token_id)")
        }
        #endif

        if llama_vocab_is_eog(vocab, new_token_id) || n_cur == n_len {
            dprint("\n")
            #if DEBUG
            if llama_vocab_is_eog(vocab, new_token_id) {
                print("🏁 [LibLlama] EOG token reached")
            } else {
                print("🏁 [LibLlama] Max length (\(n_len)) reached")
            }
            print("🏁 [LibLlama] Total tokens: \(n_decode)")
            #endif
            SystemLog().logEvent(event: "[LibLlama] Generation finished: \(n_decode) tokens")

            is_done = true
            let new_token_str = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            return new_token_str
        }

        let new_token_cchars = token_to_piece(token: new_token_id)
        temporary_invalid_cchars.append(contentsOf: new_token_cchars)
        let new_token_str: String
        if let string = String(validatingUTF8: temporary_invalid_cchars + [0]) {
            temporary_invalid_cchars.removeAll()
            new_token_str = string
        } else if (0 ..< temporary_invalid_cchars.count).contains(where: {$0 != 0 && String(validatingUTF8: Array(temporary_invalid_cchars.suffix($0)) + [0]) != nil}) {
            let string = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            new_token_str = string
        } else {
            new_token_str = ""
        }
        dprint(new_token_str)

        #if DEBUG
        if n_decode % 10 == 0 {
            print("📊 [LibLlama] Generated \(n_decode) tokens...")
        }
        #endif

        llama_batch_clear(&batch)
        llama_batch_add(&batch, new_token_id, n_cur, [0], true)

        #if DEBUG
        if n_decode % 10 == 0 || n_decode < 3 {
            print("🔢 [LibLlama] Batch state for token #\(n_decode):")
            print("   - n_tokens: \(batch.n_tokens)")
            print("   - token_id: \(new_token_id)")
            print("   - position: \(n_cur)")
            print("   - sequence: [0]")
        }
        #endif

        n_decode += 1
        n_cur    += 1

        if llama_decode(context, batch) != 0 {
            let error = "failed to evaluate llama!"
            print(error)
            #if DEBUG
            print("❌ [LibLlama] \(error)")
            print("   - n_decode: \(n_decode)")
            print("   - n_cur: \(n_cur)")
            print("   - batch.n_tokens: \(batch.n_tokens)")
            #endif
            SystemLog().logEvent(event: "[LibLlama] ERROR: \(error)")
        }

        return new_token_str
    }

    func request_stop() {
        // 外部からの停止要求
        is_done = true
    }

    func bench(pp: Int, tg: Int, pl: Int, nr: Int = 1) -> String {
        var pp_avg: Double = 0
        var tg_avg: Double = 0

        var pp_std: Double = 0
        var tg_std: Double = 0

        for _ in 0..<nr {
            // bench prompt processing

            llama_batch_clear(&batch)

            let n_tokens = pp

            for i in 0..<n_tokens {
                llama_batch_add(&batch, 0, Int32(i), [0], false)
            }
            batch.logits[Int(batch.n_tokens) - 1] = 1 // true

            llama_memory_clear(llama_get_memory(context), false)

            let t_pp_start = DispatchTime.now().uptimeNanoseconds / 1000;

            if llama_decode(context, batch) != 0 {
                print("llama_decode() failed during prompt")
            }
            llama_synchronize(context)

            let t_pp_end = DispatchTime.now().uptimeNanoseconds / 1000;

            // bench text generation

            llama_memory_clear(llama_get_memory(context), false)

            let t_tg_start = DispatchTime.now().uptimeNanoseconds / 1000;

            for i in 0..<tg {
                llama_batch_clear(&batch)

                for j in 0..<pl {
                    llama_batch_add(&batch, 0, Int32(i), [Int32(j)], true)
                }

                if llama_decode(context, batch) != 0 {
                    print("llama_decode() failed during text generation")
                }
                llama_synchronize(context)
            }

            let t_tg_end = DispatchTime.now().uptimeNanoseconds / 1000;

            llama_memory_clear(llama_get_memory(context), false)

            let t_pp = Double(t_pp_end - t_pp_start) / 1000000.0
            let t_tg = Double(t_tg_end - t_tg_start) / 1000000.0

            let speed_pp = Double(pp)    / t_pp
            let speed_tg = Double(pl*tg) / t_tg

            pp_avg += speed_pp
            tg_avg += speed_tg

            pp_std += speed_pp * speed_pp
            tg_std += speed_tg * speed_tg

            print("pp \(speed_pp) t/s, tg \(speed_tg) t/s")
        }

        pp_avg /= Double(nr)
        tg_avg /= Double(nr)

        if nr > 1 {
            pp_std = sqrt(pp_std / Double(nr - 1) - pp_avg * pp_avg * Double(nr) / Double(nr - 1))
            tg_std = sqrt(tg_std / Double(nr - 1) - tg_avg * tg_avg * Double(nr) / Double(nr - 1))
        } else {
            pp_std = 0
            tg_std = 0
        }

        let model_desc     = model_info();
        let model_size     = String(format: "%.2f GiB", Double(llama_model_size(model)) / 1024.0 / 1024.0 / 1024.0);
        let model_n_params = String(format: "%.2f B", Double(llama_model_n_params(model)) / 1e9);
        let backend        = "Metal";
        let pp_avg_str     = String(format: "%.2f", pp_avg);
        let tg_avg_str     = String(format: "%.2f", tg_avg);
        let pp_std_str     = String(format: "%.2f", pp_std);
        let tg_std_str     = String(format: "%.2f", tg_std);

        var result = ""

        result += String("| model | size | params | backend | test | t/s |\n")
        result += String("| --- | --- | --- | --- | --- | --- |\n")
        result += String("| \(model_desc) | \(model_size) | \(model_n_params) | \(backend) | pp \(pp) | \(pp_avg_str) ± \(pp_std_str) |\n")
        result += String("| \(model_desc) | \(model_size) | \(model_n_params) | \(backend) | tg \(tg) | \(tg_avg_str) ± \(tg_std_str) |\n")

        return result;
    }

    func clear() {
        #if DEBUG
        print("🧹 [LibLlama] Clearing llama state...")
        #endif

        tokens_list.removeAll()
        temporary_invalid_cchars.removeAll()

        // Clear KV cache and memory
        llama_memory_clear(llama_get_memory(context), false)

        // Reset counters
        n_cur = 0
        n_decode = 0
        is_done = false

        #if DEBUG
        print("✅ [LibLlama] State cleared")
        #endif
    }

    private func tokenize(text: String, add_bos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let n_tokens = utf8Count + (add_bos ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: n_tokens)
        let tokenCount = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(n_tokens), add_bos, false)

        var swiftTokens: [llama_token] = []
        for i in 0..<tokenCount {
            swiftTokens.append(tokens[Int(i)])
        }

        tokens.deallocate()

        return swiftTokens
    }

    /// - note: The result does not contain null-terminator
    private func token_to_piece(token: llama_token) -> [CChar] {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: Int8(0), count: 8)
        defer {
            result.deallocate()
        }
        let nTokens = llama_token_to_piece(vocab, token, result, 8, 0, false)

        if nTokens < 0 {
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-nTokens))
            newResult.initialize(repeating: Int8(0), count: Int(-nTokens))
            defer {
                newResult.deallocate()
            }
            let nNewTokens = llama_token_to_piece(vocab, token, newResult, -nTokens, 0, false)
            let bufferPointer = UnsafeBufferPointer(start: newResult, count: Int(nNewTokens))
            return Array(bufferPointer)
        } else {
            let bufferPointer = UnsafeBufferPointer(start: result, count: Int(nTokens))
            return Array(bufferPointer)
        }
    }
}

#else
// MARK: - iOS Stub Implementation (DISABLE_LLAMA)

// Stub LlamaContext for iOS when llama framework is disabled
actor LlamaContext {
    var is_done: Bool = false
    var n_len: Int32 = 1024
    private var n_cur: Int32 = 0
    private var n_decode: Int32 = 0

    init(model: OpaquePointer, context: OpaquePointer, initialNLen: Int32 = 1024) {
        self.n_len = initialNLen
        print("[LlamaContext Stub] Initialized with stub implementation (llama disabled for iOS)")
    }

    static func create_context(path: String) throws -> LlamaContext {
        print("[LlamaContext Stub] create_context called - returning stub (llama disabled for iOS)")
        // Return a dummy context - we can't actually create OpaquePointers, so this will fail
        // Instead, throw an error
        throw LlamaError.couldNotInitializeContext
    }

    func model_info() -> String {
        return "[Stub] LLM functionality disabled for iOS"
    }

    func system_info() -> String {
        return "[Stub] LLM functionality disabled for iOS"
    }

    func set_verbose(_ on: Bool) {
        // No-op
    }

    func configure_sampling(temp: Float, top_k: Int32, top_p: Float, seed: UInt64 = 1234) {
        // No-op
    }

    func set_n_len(_ value: Int32) {
        self.n_len = value
    }

    func get_n_tokens() -> Int32 {
        return 0
    }

    func completion_init(text: String) {
        print("[LlamaContext Stub] completion_init called with: \(text.prefix(50))...")
        is_done = true
    }

    func completion_loop() -> String {
        is_done = true
        return ""
    }

    func request_stop() {
        is_done = true
    }

    func bench(pp: Int, tg: Int, pl: Int, nr: Int = 1) -> String {
        return "[Stub] Benchmarking disabled for iOS"
    }

    func clear() {
        // No-op
    }
}

#endif
