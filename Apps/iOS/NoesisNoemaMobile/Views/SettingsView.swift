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
    @State private var selectedLLMModel: String = "Jan-V1-4B"
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
    }

    // MARK: - Model Section
    @ViewBuilder
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Model")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        Text(modelManager.currentLLMModel.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    if isAutotuningModel {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if runtimeMode == .override {
                        Text("Custom")
                            .font(.caption2)
                            .foregroundStyle(.orange)
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
                .foregroundStyle(.secondary)

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
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Runtime Section
    @ViewBuilder
    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime Parameters")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

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
                        .foregroundStyle(.secondary)

                    Text("Manual parameter tuning is available here. Use with caution.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                        .foregroundStyle(.yellow)
                    Text(warn)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Text("Recommended settings are automatically optimized for your device. Override only if you need manual control.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - RAG Document Section
    @ViewBuilder
    private var ragDocumentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RAG Document")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

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
                        .foregroundStyle(.secondary)
                    Text(path)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            Text("Import a .zip file containing documents for retrieval-augmented generation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Advanced Section
    @ViewBuilder
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle("Print Tokens", isOn: $debugPrintTokens)
                .font(.system(size: 15))

            Toggle("Show Timing", isOn: $debugTiming)
                .font(.system(size: 15))

            Toggle("Memory Monitoring", isOn: $debugMemory)
                .font(.system(size: 15))

            Text("Debug options for development. These are placeholder toggles and do not affect functionality yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
