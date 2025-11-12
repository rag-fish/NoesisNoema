Title: Fix missing LLM response generation and verify tokenizer → RAG → model inference pipeline (macOS target)

Context
- Project: Noesis Noema (Swift-native, macOS/iOS unified LLM RAG app)
- macOS build now launches correctly and UI locks the Ask button as expected.
- However, after submitting a question:
- The app never returns a response from the LLM.
- No crash occurs — only silent hang after askRAG() is called.
- errors.txt shows inference-related logs but no generated output.
- RAGPack selection and load succeed (local JSON / embeddings verified).
- The likely root cause is within the model invocation chain (tokenizer or generation bridge call).

Goal

Ensure that when a question is asked:
	1.	The app correctly passes the input text → tokenizer → llama.cpp inference bridge → receives generated tokens.
	2.	The selected LLM (e.g. jan-v1-4b.gguf) is actually loaded in memory and generating text.
	3.	RAG context is retrieved and prepended to the model prompt.
	4.	The result is streamed back to the UI and displayed.

Tasks
	1.	Verify Model Loading (LlamaBridge.swift)
- Confirm that loadModel() initializes with the currently selected LLM path (Resources/Models/.../*.gguf).
- Log a message when model successfully loads and when inference starts:

```ts
print("🧠 Loaded model: \(modelPath)")
print("🚀 Generating response with context length \(context.count)")
```
	2.	Fix Tokenizer and Inference Bridge
- Ensure LlamaBridge or LlamaRunner correctly passes tokens into the C++ xcframework bridge.
- Validate llama_eval() or equivalent call is executed and returning non-empty output buffer.
- Add a sanity check:

```ts
guard !output.isEmpty else {
    throw LlamaError.noResponse
}
```

	3.	RAG Context Injection (RAGManager.swift or ChatViewModel.swift)
- Confirm that retrieveRelevantDocuments(for:) returns valid text segments.
- Ensure these are concatenated into the final prompt as:

```ts
finalPrompt = """
Context:
\(contextText)

Question:
\(userInput)
"""
```

	4.	Streaming Output Handling (ChatViewModel.swift)
- Add progress callback or token-by-token stream to the main thread:
```ts
for token in llamaStream.generateTokens(prompt: finalPrompt) {
    await MainActor.run { self.lastResponse += token }
}
```

- Ensure isGenerating is set to false when streaming completes.

	5.	Cross-check Async Flow
- All await boundaries in generateAsyncAnswer() must occur on MainActor for state-safe updates.
- Use explicit Task { @MainActor in ... } when bridging async callbacks from the llama.cpp C layer.

Verification Steps
- Launch macOS build.
- Load a local RAGPack (JSON or embeddings-based).
- Select LLM (e.g. jan-v1-4b).
- Type a short contextual question (e.g. “Summarize section 2.”).
- Observe:
- “🧠 Loaded model” printed in logs.
- Response tokens appear progressively in the chat window.
- No hang or missing output.
- Confirm errors.txt remains clean (no tokenizer or memory errors).

Acceptance Criteria

✅ RAG context injection verified (context prepended to model prompt).
✅ LLM generates non-empty token sequence via llama.cpp bridge.
✅ Response displayed in UI.
✅ No infinite wait or silent failure after pressing Ask.
✅ Works for both macOS and iOS targets using respective .xcframeworks.

Notes
- Do not rebuild xcframeworks or modify the model binaries.
- Focus only on the Swift layer: LlamaBridge.swift, ChatViewModel.swift, and RAGManager.swift.
- Keep logging verbose for debug runs (#if DEBUG).
