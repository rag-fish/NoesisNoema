//
//  EmbeddingModelSmokeTests.swift
//  NoesisNoemaTests
//
//  ADR-0011 PR-A: smoke test for the real semantic EmbeddingModel.
//
//  NOTE ON RUNNING: this test needs the embedder GGUF
//  (nomic-embed-text-v1.5.Q5_K_M.gguf) reachable via Bundle.main. When the
//  NoesisNoemaTests target is hosted by the NoesisNoema app (which bundles the
//  git-ignored GGUF), the test runs end-to-end. If the GGUF is NOT in the test
//  host bundle, `EmbeddingModel(name:)` loads no context (dimension == 0) and the
//  body self-skips with a recorded note rather than failing — document the manual
//  run in the PR. (See memory: the NoesisNoemaTests target wiring is incomplete;
//  Taka runs these manually on his Mac.)
//

import Testing
import Foundation
@testable import NoesisNoema

@Suite struct EmbeddingModelSmokeTests {

    @Test func embedProducesNormalized768Vector() throws {
        let model = EmbeddingModel(name: "default")

        // Self-skip if the embedder GGUF isn't reachable in this runner's bundle.
        guard model.dimension > 0 else {
            Issue.record("Embedder GGUF not reachable via Bundle.main in this test host; skipping. Run manually with the GGUF bundled.")
            return
        }

        let v1 = model.embed(text: "hello world")

        // 3. 768 dimensions.
        #expect(v1.count == 768)

        // 4. L2 norm within 0.001 of 1.0.
        let norm = sqrt(v1.reduce(Float(0)) { $0 + $1 * $1 })
        #expect(abs(norm - 1.0) < 0.001)

        // 5. Cache-hit determinism: same input → identical vector.
        let v1again = model.embed(text: "hello world")
        #expect(v1 == v1again)

        // 6. Different text → different vector (basic semantic check).
        let v2 = model.embed(text: "entirely different text")
        #expect(v1 != v2)
    }
}
