## ParamBandit: Thompson Sampling to Select Optimal Parameters per Query 🔬

- What: A lightweight bandit that dynamically selects retrieval parameters (top_k, mmr_lambda, min_score) per query cluster.
- Why: Quickly improves relevance with minimal feedback and provides the feeling of a system that is learning.
- Where: Just before the generator, immediately before the retrieval pipeline.
- How:
  - Maintains Beta(α,β) distributions for each arm (parameter set) and selects using Thompson Sampling.
  - Updates α/β based on feedback events (👍/👎) from the RewardBus.
  - Example default arms: k4/l0.7/s0.20, k5/l0.9/s0.10, k6/l0.7/s0.15, k8/l0.5/s0.15.

Usage example (integration concept)
- Call ParamBandit just before existing LocalRetriever usage points, and perform retrieval with the returned parameters.
- On the UI side, trigger RewardBus.shared.publish(qaId:verdict:tags:) upon user feedback (👍/👎).

Simplified flow:
1) let qa = UUID()
2) let choice = ParamBandit.default.chooseParams(for: query, qaId: qa)
3) let ps = choice.arm.params // topK, mmrLambda, minScore
4) let chunks = LocalRetriever(store: .shared).retrieve(query: query, k: ps.topK, lambda: ps.mmrLambda)
5) Filter by minScore for similarity (see BanditRetriever)
6) On user evaluation, call RewardBus.shared.publish(qaId: qa, verdict: .up/.down, tags: …)

Tests and Definition of Done (DoD)
- Unit: Verify initial α=1, β=1, and that 👍 increments α and 👎 increments β (add to TestRunner, skip in CLI build).
- Integration: Confirm preference converges to the best arm with composite rewards (same as above).
- DoD: Add ParamBandit as an independent service, integrate with RewardBus, define default arms, and provide lightweight documentation (this section).
