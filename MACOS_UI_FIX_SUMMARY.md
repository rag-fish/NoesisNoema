# macOS UI Functional Fix Summary

## Problem
After successfully fixing the dylib embedding issues, the macOS app launched but had several critical functional problems:

1. **Model Pickers Not Working**: LLM and Embedding model dropdowns were empty or not responding to selection changes
2. **Ask Button Non-Functional**: Clicking "Ask" button had no effect - no inference was triggered
3. **RAGpack Upload Issues**: Uploading .zip RAGpack files could cause UI blocking or runtime errors

## Root Causes

### 1. Model Picker Issue
- `ContentView` used computed properties to access `ModelManager.shared.availableModels`
- The `ModelManager` is `@ObservableObject` with `@Published var availableModels`
- However, ContentView was not observing the ModelManager, so UI didn't update when models loaded
- Models are loaded asynchronously in `ModelManager.init()`, so initial UI rendering showed empty pickers

### 2. Ask Button Issue
- `ModelManager.generateAsyncAnswer()` was just a stub returning `"[model_name] question"`
- No actual RAG retrieval or LLM inference was happening
- The full RAG infrastructure (LocalRetriever, VectorStore, LLMModel.generate) existed but wasn't connected

### 3. RAGpack Upload Issue
- `DocumentManager.importDocument()` was synchronous and running heavy work on main thread:
  - ZIP extraction
  - JSON parsing
  - CSV loading
  - Array operations
- This blocked the UI and could cause thread-safety issues with `@Published` properties

## Solutions Implemented

### 1. Fix Model Pickers
**File**: `NoesisNoema/Shared/ContentView.swift`

```swift
// Before: Not observing ModelManager
struct ContentView: View {
    var availableLLMModels: [String] { ModelManager.shared.availableLLMModels }
    ...
}

// After: Observe ModelManager for reactive updates
struct ContentView: View {
    @ObservedObject var modelManager = ModelManager.shared
    var availableLLMModels: [String] { modelManager.availableLLMModels }

    // Added onAppear to sync state
    .onAppear {
        selectedEmbeddingModel = ModelManager.shared.currentEmbeddingModel.name
        selectedLLMModel = ModelManager.shared.currentLLMModel.name
        selectedLLMPreset = ModelManager.shared.currentLLMPreset
    }
}
```

### 2. Implement Full RAG Pipeline
**File**: `NoesisNoema/Shared/ModelManager.swift`

```swift
// Before: Stub implementation
func generateAsyncAnswer(question: String) async -> String {
    return "[\(currentLLMModel.name)] \(question)"
}

// After: Full RAG implementation
func generateAsyncAnswer(question: String) async -> String {
    // 1. Retrieve relevant chunks using LocalRetriever
    let retriever = LocalRetriever(store: VectorStore.shared)
    let chunks = retriever.retrieve(query: question, k: 5, trace: false)

    // Store chunks for citation UI
    lastRetrievedChunks = chunks

    // 2. Build context from chunks
    let context = chunks.map { $0.content }.joined(separator: "\n\n")

    // 3. Generate answer using LLM
    let answer = currentLLMModel.generate(prompt: question, context: context.isEmpty ? nil : context)

    return answer
}
```

### 3. Fix RAGpack Upload Threading
**File**: `NoesisNoema/Shared/DocumentManager.swift`

```swift
// Before: Synchronous blocking operation
func importDocument(file: Any) {
    // All heavy work on main thread
    // ZIP extraction, JSON parsing, etc.
    self.llmragFiles.append(ragFile)  // Direct mutation on unknown thread
}

// After: Async with proper thread management
@MainActor
func importDocument(file: Any) {
    Task.detached {
        await self.processRAGpackImport(fileURL: fileURL)
    }
}

private func processRAGpackImport(fileURL: URL) async {
    // Heavy work on background thread
    // ZIP extraction, JSON parsing, etc.

    // UI updates on main thread
    await MainActor.run {
        self.llmragFiles.append(ragFile)
        VectorStore.shared.chunks.append(contentsOf: uniqueChunks)
        self.uploadHistory.append(...)
        self.saveHistory()
    }
}
```

## Technical Details

### RAG Flow
1. **Retrieval**: `LocalRetriever` performs hybrid BM25 + embedding search on `VectorStore`
2. **Context Building**: Top 5 relevant chunks are concatenated with `\n\n` separator
3. **Inference**: `LLMModel.generate()` receives question + context, applies model-specific prompt template (Jan vs. plain), and runs llama.cpp inference
4. **Citation Support**: Retrieved chunks stored in `lastRetrievedChunks` for UI to display sources

### Threading Model
- **Main Actor**: UI updates, SwiftUI state changes, @Published property mutations
- **Background**: Heavy I/O operations (ZIP extraction, file parsing)
- **Task.detached**: Ensures background work doesn't inherit main actor context
- **MainActor.run**: Explicitly jumps to main thread for UI updates

## Verification

✅ **Model Pickers**: Populate with 3 models (jan_v1_4b_q4_k_m, llama_3_3_70b_instruct_ud_iq1_s, gpt_oss_20b_f16)
✅ **Ask Button**: Triggers full RAG pipeline with retrieval + inference
✅ **RAGpack Upload**: Non-blocking UI, proper thread safety
✅ **No Runtime Errors**: Clean app launch and operation
✅ **Build**: No warnings or errors

## Next Steps

The macOS UI is now fully functional. Users can:
- Select LLM and embedding models from dropdowns
- Enter questions and get RAG-powered answers
- Upload RAGpack .zip files without UI freezing
- View citations from retrieved sources

All three critical issues are resolved.
