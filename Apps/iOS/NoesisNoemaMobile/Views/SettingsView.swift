//
//  SettingsView.swift
//  NoesisNoemaMobile
//
//  Created by Раскольников on 2025/11/27.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject private var modelManager = ModelManager.shared

    @State private var selectedEmbeddingModel: String = "default-embedding"
    @State private var selectedLLMModel: String = "Llama 3.2 3B"
    @State private var selectedLLMPreset: String = ModelManager.shared.currentLLMPreset
    @State private var isAutotuningModel: Bool = false
    @State private var recommendedReady: Bool = false
    @State private var autotuneWarning: String? = nil
    @State private var runtimeMode: RuntimeMode = ModelManager.shared.getRuntimeMode()
    @State private var useRecommended: Bool = true
    @State private var showOverridePanel: Bool = false
    @State private var showImporter = false
    @State private var lastImportedPath: String? = nil

    // Placeholder debug toggles
    @State private var debugPrintTokens: Bool = false
    @State private var debugTiming: Bool = false
    @State private var debugMemory: Bool = false

    // Retrieval: Deep Search opt-in. Persisted in UserDefaults and read by
    // LocalExecutor (off by default — DeepSearch runs heavier multi-round
    // retrieval). Fully on-device, so R3's privacy guarantee is unaffected.
    @AppStorage(LocalExecutor.deepSearchDefaultsKey) private var deepSearchEnabled: Bool = false

    // Debug: present the MinimalClientView (EPIC1 vertical-slice) screen.
    @State private var showMinimalClient: Bool = false

    var availableEmbeddingModels: [String] { ModelManager.shared.availableEmbeddingModels }
    var availableLLMModels: [String] { ModelManager.shared.availableLLMModels }
    var availableLLMPresets: [String] { ModelManager.shared.availableLLMPresets }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                modelSection
                presetSection
                runtimeSection
                ragDocumentSection
                retrievalSection
                advancedSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
        .background(Color.white)
        .onAppear {
            runtimeMode = ModelManager.shared.getRuntimeMode()
            useRecommended = (runtimeMode == .recommended)
        }
        .sheet(isPresented: $showMinimalClient) {
            // Debug screen reached from Advanced ▸ Open Minimal Client.
            // It is a self-contained diagnostic; a fresh coordinator is fine
            // (HybridExecutionCoordinator is stateless).
            MinimalClientView(executionCoordinator: HybridExecutionCoordinator())
        }
    }

    // MARK: - Retrieval Section
    @ViewBuilder
    private var retrievalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Retrieval")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            Toggle("Deep Search", isOn: $deepSearchEnabled)
                .font(.system(size: 15))

            Text("Multi-round local query expansion for broader retrieval. Runs fully on-device. Slower than standard retrieval — off by default.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Model Section
    @ViewBuilder
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Model")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        Text(modelManager.currentLLMModel.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    if isAutotuningModel {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if runtimeMode == .override {
                        Text("Custom")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }

                Button(action: { showModelPicker() }) {
                    Label("Change Model", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Preset Section
    @ViewBuilder
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preset")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            Picker("Preset", selection: $selectedLLMPreset) {
                ForEach(availableLLMPresets, id: \.self) { preset in
                    Text(preset).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedLLMPreset) { newValue in
                ModelManager.shared.setLLMPreset(name: newValue)
            }

            Text("Auto adjusts parameters based on your model. Choose Balanced, Creative, or Precise for specific behaviors.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Runtime Section
    @ViewBuilder
    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime Parameters")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            Toggle("Use Recommended", isOn: $useRecommended)
                .onChange(of: useRecommended) { newValue in
                    if newValue {
                        runtimeMode = .recommended
                        showOverridePanel = false
                        ModelManager.shared.setRuntimeMode(.recommended)
                        recommendedReady = true
                    } else {
                        runtimeMode = .override
                        showOverridePanel = true
                        ModelManager.shared.setRuntimeMode(.override)
                    }
                }

            if showOverridePanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Override Panel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text("Manual parameter tuning is available here. Use with caution.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Reset to Recommended") {
                        ModelManager.shared.resetToRecommended()
                        useRecommended = true
                        runtimeMode = .recommended
                        recommendedReady = true
                        showOverridePanel = false
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                .padding(.vertical, 8)
            }

            if let warn = autotuneWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(warn)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            Text("Recommended settings are automatically optimized for your device. Override only if you need manual control.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - RAG Document Section
    @ViewBuilder
    private var ragDocumentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RAG Document")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            Button {
                showImporter = true
            } label: {
                Label("Choose File", systemImage: "doc.zipper")
                    .font(.system(size: 15))
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.zip]) { result in
                if case let .success(url) = result {
                    documentManager.importDocument(file: url)
                    lastImportedPath = url.lastPathComponent
                }
            }

            if let path = lastImportedPath {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Imported")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(path)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }

            Text("Import a .zip file containing documents for retrieval-augmented generation.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Advanced Section
    @ViewBuilder
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            Toggle("Print Tokens", isOn: $debugPrintTokens)
                .font(.system(size: 15))

            Toggle("Show Timing", isOn: $debugTiming)
                .font(.system(size: 15))

            Toggle("Memory Monitoring", isOn: $debugMemory)
                .font(.system(size: 15))

            Text("Debug options for development. These are placeholder toggles and do not affect functionality yet.")
                .font(.caption)
                .foregroundColor(.secondary)

            #if DEBUG
            Divider()
                .padding(.vertical, 4)

            Button {
                showMinimalClient = true
            } label: {
                Label("Open Minimal Client", systemImage: "ladybug")
                    .font(.system(size: 15))
            }
            .buttonStyle(.bordered)

            Text("EPIC1 vertical-slice debug screen (prompt → coordinator → response). Debug builds only; not shipped in Release.")
                .font(.caption)
                .foregroundColor(.secondary)
            #endif
        }
    }

    // MARK: - Helper Methods
    private func showModelPicker() {
        // Placeholder for a real model picker
    }
}

#Preview {
    SettingsView(documentManager: DocumentManager())
}
