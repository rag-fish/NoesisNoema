You will modify the Swift source file `main.swift` for Noesis/Noema's LlamaBridgeTest CLI.
Focus only on the functions `cleanOutput(_:)` and the post-processing portion of `infer(_:)`.

### GOAL
Ensure that the CLI always returns a clean, final answer from Jan/Qwen3-style chat models.
The current output still includes:
- `<|im_start|>user ...`
- `<|im_start|>assistant`, `<|im_end|>`
- partial template fragments (e.g., `<|im`)
- meta reasoning such as “We are given a history…”
- leftover `<think>` blocks

### REQUIRED CHANGES

#### 1. Replace `cleanOutput(_:)` with a robust version:
- Remove ALL:
  - `<think>...</think>`
  - `<|im_start|>*` blocks except the final assistant block
  - `<|im_end|>`
  - any broken fragments like `<|im`, `<im`, `</im`
- Detect the last `<|im_start|>assistant` block and extract ONLY its content.
- Trim whitespace and newlines.

#### 2. Modify `infer(_:)` final output assembly:
After token generation completes and `cleanOutput` is applied:
- Split into lines.
- Remove any line that contains meta-commentary or analysis patterns:
  - “history of previous interactions”
  - “we are given”
  - “analysis”
  - “chain-of-thought”
  - “meta”
- Choose the longest remaining paragraph as the final answer.
- If no valid content remains, fallback to the raw cleaned text.

#### 3. Conditions:
- Do NOT modify LlamaContext calls.
- Do NOT touch sampling logic.
- Keep the inference loop exactly as-is.
- Only edit: `cleanOutput(_:)` and the section after `let cleaned = cleanOutput(acc)` inside `infer(_:)`.

### OUTPUT FORMAT
Produce a unified diff patch (Git style) that I can paste directly into BBEdit.
