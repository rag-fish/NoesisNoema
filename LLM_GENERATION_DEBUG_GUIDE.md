# LLM Generation Pipeline Debug Guide

## Overview
This document explains the debugging instrumentation added to diagnose and fix missing LLM response generation in the macOS/iOS targets.

## Debug Logging Added

### 1. ModelManager.generateAsyncAnswer
**Location:** `NoesisNoema/Shared/ModelManager.swift`

**Logs:**
- 🚀 Generation start with question preview
- 📚 RAG context retrieval (chunk count and previews)
- 📝 Context building (character count)
- 🧠 LLM model selection and file path
- 💬 Response length and preview
- ✅ Total generation time

**Key Indicators:**
- If you see "🚀 Starting generation" but no "💬 LLM response", the problem is in LLMModel.generate()
- If chunk count is 0, RAG retrieval may be failing
- Empty response preview indicates model inference problem

### 2. LLMModel.runInference
**Location:** `NoesisNoema/Shared/LLMModel.swift`

**Logs:**
- 🎯 Inference start with model name and context availability
- 🧠 Model file location (first successful path match)
- 🔄 LlamaState initialization
- ✅ Model load success
- ⚙️ Preset selection (auto or manual)
- 🚀 Generation start with prompt preview
- 📥 Raw response length
- ⚠️ Fallback attempts if needed
- ✅/❌ Final result or errors

**Key Indicators:**
- If no "🧠 Found model file", check model file paths
- If "❌ Empty response from LLM", the llama.cpp bridge is not generating
- If fallback is triggered, primary prompt format may be incompatible

### 3. LlamaState.loadModel
**Location:** `NoesisNoema/Shared/Llama/LlamaState.swift`

**Logs:**
- 🔄 Model loading start with full path
- ✅ Model loaded successfully
- ℹ️ System info from llama.cpp

**Key Indicators:**
- If loading fails, check file permissions and .gguf file integrity
- System info shows CPU/GPU capabilities

### 4. LlamaState.complete
**Location:** `NoesisNoema/Shared/Llama/LlamaState.swift`

**Logs:**
- 🎬 Completion start with prompt length
- 🔥 Heat-up time
- 🎉 First token received
- 📊 Token count (every 10 tokens)
- ⏱️ Generation timeout warnings
- ⚡ Final speed (tokens/second)
- ✨ Normalized response length
- ⚠️ Empty answer warnings

**Key Indicators:**
- If no "🎉 First token received", the model is not generating
- If timeout occurs, model may be too large for hardware
- Token speed <1 t/s indicates performance issues

## Testing Procedure

### Step 1: Enable Console Logging
```bash
# Open Console.app
# Filter for "NoesisNoema" or emoji indicators
```

### Step 2: Test Basic Generation
1. Launch the macOS app
2. Select an LLM model from picker (e.g., "Jan-V1-4B")
3. Enter a simple question: "What is 2+2?"
4. Click "Ask"
5. Monitor console output

**Expected Log Sequence:**
```
🚀 [ModelManager] Starting generation for question: What is 2+2?...
📚 [ModelManager] Retrieving RAG context...
📚 [ModelManager] Retrieved 0 chunks
📝 [ModelManager] Built context with 0 characters
🧠 [ModelManager] Calling LLM model: Jan-V1-4B
🎯 [LLMModel] runInference called for model: Jan-V1-4B
🧠 [LLMModel] Found model file at: /path/to/Jan-v1-4B-Q4_K_M.gguf
🔄 [LLMModel] Loading model into LlamaState...
✅ [LLMModel] Model loaded successfully
⚙️ [LLMModel] Auto-selected preset: balanced
🚀 [LLMModel] Generating response with context length 0
🎬 [LlamaState] Starting completion for prompt length: XXX
🔥 [LlamaState] Heat up completed in X.XXs
🎉 [LlamaState] First token received!
📊 [LlamaState] Generated 10 tokens...
...
⏱️ [LlamaState] Generation completed in X.XXs
⚡ [LlamaState] Speed: XX.XX tokens/s
📝 [LlamaState] Raw response length: XXX
✨ [LlamaState] Normalized response length: XXX
💬 [ModelManager] LLM response length: XXX chars
✅ [ModelManager] Generation completed in XXXms
```

### Step 3: Test RAG Context
1. Upload a RAGPack (.zip with documents)
2. Ask a question about the content
3. Verify "Retrieved N chunks" where N > 0
4. Check "Built context with XXX characters" shows context data

### Step 4: Test Different Models
1. Switch between Jan-V1-4B and llama3-8b
2. Verify each model loads correctly
3. Check preset selection logs

## Common Issues and Solutions

### Issue 1: No Response Generated
**Symptoms:**
- "❌ Empty response from LLM!" in logs
- UI shows blank answer

**Diagnosis:**
- Check if "🎉 First token received!" appears
- If missing, llama.cpp bridge is not executing

**Solutions:**
- Verify model file is valid GGUF format
- Check available RAM (model too large)
- Try smaller model (e.g., Jan-V1-4B vs llama3-8b)
- Rebuild xcframeworks if bridge is broken

### Issue 2: Model File Not Found
**Symptoms:**
- "❌ Model file not found: filename.gguf"
- Lists checked paths

**Solutions:**
- Verify model exists in Resources/Models/
- Check Xcode "Copy Bundle Resources" includes .gguf files
- Ensure model file name matches exactly (case-sensitive)

### Issue 3: Generation Timeout
**Symptoms:**
- "⏱️ Generation timeout after 20.00s"
- Partial or no response

**Solutions:**
- Increase timeout in LlamaState.swift (GENERATION_TIMEOUT_S)
- Use smaller model
- Reduce max tokens (nLen in preset)
- Check system resources (Activity Monitor)

### Issue 4: RAG Context Not Retrieved
**Symptoms:**
- "Retrieved 0 chunks" every time
- Context length always 0

**Solutions:**
- Verify RAGPack is loaded (check DocumentManager)
- Ensure embeddings are generated
- Check VectorStore.shared has data
- Test retriever directly with trace=true

### Issue 5: Wrong Model Loaded
**Symptoms:**
- Log shows different model than UI selection
- Unexpected responses

**Solutions:**
- Check ModelManager.currentLLMModel
- Verify switchLLMModelByID is called
- Check UserDefaults persistence

## Performance Benchmarks

### Expected Performance (M1/M2 MacBook)

**Jan-V1-4B (4B params, Q4_K_M quantization):**
- Heat-up: 0.5-2s
- Generation: 15-30 tokens/s
- Memory: ~3-4 GB

**Llama3-8B (8B params, Q4_0 quantization):**
- Heat-up: 1-4s
- Generation: 8-20 tokens/s
- Memory: ~5-8 GB

### Red Flags:
- Heat-up >5s (model may be too large)
- Generation <5 t/s (performance issue)
- Memory spike >12 GB (swap thrashing)

## Debugging Commands

### Check Model Files
```bash
ls -lh NoesisNoema/Resources/Models/
file NoesisNoema/Resources/Models/*.gguf
```

### Monitor Console in Real-Time
```bash
log stream --predicate 'process == "NoesisNoema"' --level debug
```

### Check System Logs
```bash
log show --predicate 'process == "NoesisNoema"' --last 5m --info
```

### Profile Memory Usage
```bash
leaks NoesisNoema
vmmap -summary $(pgrep NoesisNoema)
```

## Next Steps if Issues Persist

1. **Enable LlamaContext verbose mode:**
   - Call `await llamaState.setVerbose(true)` before generation
   - Check for C++ layer errors

2. **Test with minimal prompt:**
   - Use "Hi" as question
   - No RAG context
   - Simplest possible case

3. **Verify xcframework integrity:**
   - Check llama.framework symbols
   - Ensure Metal/CPU backends present
   - Validate architecture (arm64/x86_64)

4. **Create standalone test:**
   - Use LlamaBridgeTest CLI target
   - Isolate llama.cpp layer
   - Test direct C++ bridge calls

## Code References

- `ModelManager.generateAsyncAnswer()` - High-level RAG + LLM orchestration
- `LLMModel.runInference()` - Model file resolution and LlamaState setup
- `LlamaState.complete()` - Token-by-token generation loop
- `LlamaContext` - C++ bridge to llama.cpp

## Debug Build Configuration

All logging is wrapped in `#if DEBUG` blocks and only active in Debug builds.
For Release builds, logging is stripped to improve performance.

To force logging in Release:
1. Add `-DDEBUG` to "Other Swift Flags" in Release configuration
2. Or use SystemLog() which persists to file in both builds
