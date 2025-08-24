// filepath: NoesisNoema/Shared/RAG/ParamBandit.swift
// Description: Thompson Sampling-based parameter bandit for retrieval.
// License: MIT

import Foundation
import Combine

// MARK: - Parameter Set
struct RetrievalParams: Codable, Hashable {
    var topK: Int
    var mmrLambda: Float
    var minScore: Float
}

// MARK: - Clusterer
protocol QueryClusterer {
    func clusterId(for query: String) -> String
}

struct HashClusterer: QueryClusterer {
    init() {}
    func clusterId(for query: String) -> String {
        let norm = query.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if norm.isEmpty { return "default" }
        var hasher = Hasher()
        hasher.combine(norm)
        let v = hasher.finalize()
        let bucket = abs(v % 16)
        return "qcluster-\(bucket)"
    }
}

// MARK: - Bandit
final class ParamBandit {
    struct Arm: Hashable { let id: String; let params: RetrievalParams }
    struct BetaAB: Hashable { var alpha: Double; var beta: Double }
    
    struct Config {
        var arms: [Arm]
        var clusterer: QueryClusterer
        init(arms: [Arm], clusterer: QueryClusterer = HashClusterer()) {
            self.arms = arms
            self.clusterer = clusterer
        }
    }
    
    static let `default`: ParamBandit = {
        let arms: [Arm] = [
            Arm(id: "k4_l0.7_s0.20", params: .init(topK: 4, mmrLambda: 0.7, minScore: 0.20)),
            Arm(id: "k5_l0.9_s0.10", params: .init(topK: 5, mmrLambda: 0.9, minScore: 0.10)),
            Arm(id: "k6_l0.7_s0.15", params: .init(topK: 6, mmrLambda: 0.7, minScore: 0.15)),
            Arm(id: "k8_l0.5_s0.15", params: .init(topK: 8, mmrLambda: 0.5, minScore: 0.15))
        ]
        return ParamBandit(config: .init(arms: arms))
    }()
    
    private let config: Config
    private let rewardBus: RewardBus
    private var cancellable: AnyCancellable?
    private let urand: () -> Double
    
    // cluster -> armId -> Beta
    private var table: [String: [String: BetaAB]] = [:]
    // qaId -> (cluster, armId)
    private var selectionByQa: [UUID: (String, String)] = [:]
    private let queue = DispatchQueue(label: "param.bandit.queue")
    
    init(config: Config, rewardBus: RewardBus = RewardBus.shared, urand: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.config = config
        self.rewardBus = rewardBus
        self.urand = urand
        // init priors
        for arm in config.arms {
            table["default", default: [:]][arm.id] = BetaAB(alpha: 1, beta: 1)
        }
        // subscribe to rewards
        self.cancellable = rewardBus.subject.sink { [weak self] event in
            self?.handle(event)
        }
    }
    
    deinit { cancellable?.cancel() }
    
    // MARK: - Public API
    func chooseParams(for query: String, qaId: UUID? = nil) -> (cluster: String, arm: Arm) {
        let cluster = config.clusterer.clusterId(for: query)
        ensureCluster(cluster)
        // Thompson sample each arm
        var best: (Arm, Double) = (config.arms[0], -Double.infinity)
        for arm in config.arms {
            let ab = table[cluster]![arm.id]!
            let sample = sampleBeta(alpha: ab.alpha, beta: ab.beta)
            if sample > best.1 { best = (arm, sample) }
        }
        if let qa = qaId {
            queue.async { [weak self] in self?.selectionByQa[qa] = (cluster, best.0.id) }
        }
        return (cluster, best.0)
    }
    
    // For explicit updates in tests or integration layers
    func update(cluster: String, armId: String, reward: Bool) {
        queue.sync {
            ensureCluster(cluster)
            var ab = table[cluster]![armId] ?? BetaAB(alpha: 1, beta: 1)
            if reward { ab.alpha += 1 } else { ab.beta += 1 }
            table[cluster]![armId] = ab
        }
    }
    
    func state(cluster: String) -> [String: BetaAB] {
        return queue.sync { table[cluster] ?? [:] }
    }
    
    func arms() -> [Arm] { config.arms }
    
    // MARK: - Private
    private func handle(_ event: RewardEvent) {
        queue.async {
            guard let (cluster, armId) = self.selectionByQa[event.qaId] else { return }
            switch event.verdict {
            case .up: self.update(cluster: cluster, armId: armId, reward: true)
            case .down: self.update(cluster: cluster, armId: armId, reward: false)
            }
        }
    }
    
    private func ensureCluster(_ cluster: String) {
        if table[cluster] == nil {
            var m: [String: BetaAB] = [:]
            for a in config.arms { m[a.id] = BetaAB(alpha: 1, beta: 1) }
            table[cluster] = m
        }
    }
    
    private func sampleBeta(alpha: Double, beta: Double) -> Double {
        // Use two Gamma draws via Marsaglia and Tsang method (shape k=alpha, theta=1)
        func sampleGamma(_ k: Double) -> Double {
            if k < 1 {
                // Johnk's generator for 0<k<1
                while true {
                    let u = urand()
                    let v = urand()
                    let x = pow(u, 1.0 / k)
                    let y = pow(v, 1.0 / (1.0 - k))
                    if x + y <= 1 {
                        let w = max(urand(), 1e-12)
                        return -log(w) * x / (x + y)
                    }
                }
            }
            let d = k - 1.0/3.0
            let c = 1.0 / sqrt(9.0 * d)
            while true {
                var x: Double
                repeat { x = gaussian() } while x.isNaN
                let v = pow(1.0 + c * x, 3)
                if v <= 0 { continue }
                let u = urand()
                if u < 1 - 0.331 * pow(x, 4) { return d * v }
                if log(u) < 0.5 * x*x + d * (1 - v + log(v)) { return d * v }
            }
        }
        func gaussian() -> Double {
            // Box-Muller
            let u1 = max(urand(), 1e-12)
            let u2 = urand()
            return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        }
        let x = sampleGamma(alpha)
        let y = sampleGamma(beta)
        return x / (x + y)
    }
}
