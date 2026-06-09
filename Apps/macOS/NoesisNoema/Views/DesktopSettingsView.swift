//
//  DesktopSettingsView.swift
//  NoesisNoema (macOS)
//
//  ADR-0010 Settings section. Consolidates the v0.22 macOS controls and the iOS
//  parity controls into one native macOS Form:
//   • DeepSearch toggle (@AppStorage, shared key with iOS PR #87)
//   • Embedding model picker      → switchEmbeddingModel
//   • LLM model picker + autotune → autotuneCurrentModelAsync
//   • LLM preset picker           → setLLMPreset
//   • Runtime mode picker         → getLLMRuntimeMode / setLLMRuntimeMode
//     ( + Reset to recommended    → resetToRecommended )
//   • Offline indicator (display-only: appSettings.offline && isFullyLocal())
//   • RAGpack manager             → sheet over DocumentManager
//   • Clear History               → clears the same four stores as iOS Settings
//   • #if DEBUG "Open Minimal Client" debug entry (mirrors iOS PR #87)
//
//  Written fresh for macOS; no `ModelManager.generateAsync*` here — Settings is
//  pure configuration. The Runtime picker binds to the actual `LLMRuntimeMode`
//  cases (`.auto` / `.cpuOnly`); ADR-0010 §Scope: do not invent enum cases.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct DesktopSettingsView: View {
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var selectedEmbeddingModel: String = ModelManager.shared.currentEmbeddingModel.name
    @State private var selectedLLMModel: String = ModelManager.shared.currentLLMModel.name
    @State private var selectedLLMPreset: String = ModelManager.shared.currentLLMPreset
    @State private var runtimeMode: LLMRuntimeMode = ModelManager.shared.getLLMRuntimeMode()

    @State private var isAutotuningModel: Bool = false
    @State private var recommendedReady: Bool = false
    @State private var autotuneWarning: String? = nil

    // Retrieval: Deep Search opt-in. Persisted in UserDefaults and read by
    // LocalExecutor (off by default — heavier multi-round retrieval). Same
    // defaults key as iOS PR #87. Fully on-device.
    @AppStorage(LocalExecutor.deepSearchDefaultsKey) private var deepSearchEnabled: Bool = false

    @State private var showRAGpackManager: Bool = false
    @State private var showClearConfirm: Bool = false

    #if DEBUG
    @State private var showMinimalClient: Bool = false
    #endif

    private var availableEmbeddingModels: [String] { ModelManager.shared.availableEmbeddingModels }
    private var availableLLMModels: [String] { ModelManager.shared.availableLLMModels }
    private var availableLLMPresets: [String] { ModelManager.shared.availableLLMPresets }

    var body: some View {
        Form {
            modelSection
            presetSection
            embeddingSection
            runtimeSection
            retrievalSection
            connectivitySection
            dataSection
            #if DEBUG
            debugSection
            #endif
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Settings")
        .onAppear {
            selectedEmbeddingModel = ModelManager.shared.currentEmbeddingModel.name
            selectedLLMModel = ModelManager.shared.currentLLMModel.name
            selectedLLMPreset = ModelManager.shared.currentLLMPreset
            runtimeMode = ModelManager.shared.getLLMRuntimeMode()
        }
        .sheet(isPresented: $showRAGpackManager) {
            DesktopRAGpackManagerView(documentManager: documentManager)
        }
        #if DEBUG
        .sheet(isPresented: $showMinimalClient) {
            // EPIC1 vertical-slice debug screen. A fresh coordinator is fine —
            // HybridExecutionCoordinator is stateless. Debug builds only.
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") { showMinimalClient = false }
                }
                .padding(12)
                MinimalClientView(executionCoordinator: HybridExecutionCoordinator())
            }
            .frame(minWidth: 480, minHeight: 420)
        }
        #endif
    }

    // MARK: - Model

    private var modelSection: some View {
        Section("Model") {
            HStack {
                Picker("LLM Model", selection: $selectedLLMModel) {
                    ForEach(availableLLMModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onChange(of: selectedLLMModel) { _, newValue in
                    handleLLMModelChange(newValue)
                }

                if isAutotuningModel {
                    ProgressView().scaleEffect(0.7)
                } else if runtimeMode == .cpuOnly {
                    DesktopBadge(text: "Custom", color: .orange)
                } else if recommendedReady {
                    DesktopBadge(text: "Recommended", color: .green)
                }
            }

            if let warning = autotuneWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preset

    private var presetSection: some View {
        Section("Preset") {
            Picker("LLM Preset", selection: $selectedLLMPreset) {
                ForEach(availableLLMPresets, id: \.self) { preset in
                    Text(preset).tag(preset)
                }
            }
            .onChange(of: selectedLLMPreset) { _, newValue in
                ModelManager.shared.setLLMPreset(name: newValue)
            }
            Text("Auto adjusts parameters for your model. Balanced / Creative / Precise pick specific behaviours.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Embedding

    private var embeddingSection: some View {
        Section("Embedding") {
            Picker("Embedding Model", selection: $selectedEmbeddingModel) {
                ForEach(availableEmbeddingModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .onChange(of: selectedEmbeddingModel) { _, newValue in
                ModelManager.shared.switchEmbeddingModel(name: newValue)
            }
        }
    }

    // MARK: - Runtime

    private var runtimeSection: some View {
        Section("Runtime") {
            Picker("Runtime Mode", selection: $runtimeMode) {
                Text("Auto (GPU when available)").tag(LLMRuntimeMode.auto)
                Text("CPU only").tag(LLMRuntimeMode.cpuOnly)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: runtimeMode) { _, newValue in
                ModelManager.shared.setLLMRuntimeMode(newValue)
            }

            Button("Reset to Recommended") {
                ModelManager.shared.resetToRecommended()
                runtimeMode = ModelManager.shared.getLLMRuntimeMode()
                selectedLLMPreset = ModelManager.shared.currentLLMPreset
                recommendedReady = true
                autotuneWarning = nil
            }
            .disabled(runtimeMode == .auto)

            Text("Auto lets the runtime use the GPU when the device supports it. CPU only forces CPU execution.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Retrieval

    private var retrievalSection: some View {
        Section("Retrieval") {
            Toggle("Deep Search", isOn: $deepSearchEnabled)
            Text("Multi-round local query expansion for broader retrieval. Runs fully on-device. Slower than standard retrieval — off by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Connectivity (offline indicator)

    private var connectivitySection: some View {
        Section("Connectivity") {
            HStack {
                Toggle("Offline", isOn: $appSettings.offline)
                    .toggleStyle(.switch)
                Spacer()
                if appSettings.offline && modelManager.isFullyLocal() {
                    DesktopBadge(text: "Local Only", color: .green)
                }
            }
            Toggle("Disable macOS IME", isOn: $appSettings.disableMacOSIME)
                .toggleStyle(.switch)
            Text("Offline blocks all outbound network calls. Local Only confirms every component is on-device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section("Data") {
            Button {
                showRAGpackManager = true
            } label: {
                Label("Manage RAGpacks", systemImage: "shippingbox")
            }

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("Clear History", systemImage: "trash")
            }
            .confirmationDialog(
                "Delete all Q&A history?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) { clearAllHistory() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently removes your Q&A history, cached answers, and feedback from this device. It cannot be undone.")
            }

            Text("Import RAGpacks for retrieval, or wipe all saved Q&A history, cached answers, and feedback.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        Section("Advanced") {
            Button {
                showMinimalClient = true
            } label: {
                Label("Open Minimal Client", systemImage: "ladybug")
            }
            Text("EPIC1 vertical-slice debug screen (prompt → coordinator → response). Debug builds only; not shipped in Release.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    #endif

    // MARK: - Helpers

    private func handleLLMModelChange(_ newValue: String) {
        recommendedReady = false
        autotuneWarning = nil
        isAutotuningModel = true

        ModelManager.shared.switchLLMModel(name: newValue)
        runtimeMode = ModelManager.shared.getLLMRuntimeMode()
        selectedLLMPreset = "auto"
        ModelManager.shared.setLLMPreset(name: "auto")

        ModelManager.shared.autotuneCurrentModelAsync(trace: false, timeoutSeconds: 3.0) { warningMessage in
            isAutotuningModel = false
            recommendedReady = true
            if !warningMessage.isEmpty {
                autotuneWarning = warningMessage
            }
        }
    }

    /// Clears every store that backs user Q&A data. Invoked only after the
    /// explicit confirmation dialog — there is no auto-wipe. Same four stores as
    /// the iOS Settings "Clear History" action (PR #87).
    private func clearAllHistory() {
        documentManager.clearQAHistroy()        // qaHistory + selection + persisted file (typo is real)
        QAContextStore.shared.removeAll()       // in-memory per-QA citation context
        FeedbackStore.shared.clearAll()         // encrypted feedback file
        SemanticAnswerCache.shared.clearCache() // cached semantic answers
    }
}

// MARK: - RAGpack manager

/// macOS RAGpack manager. Lists imported packs (name + chunk count), supports
/// delete and import. macOS-local (`Desktop`-prefixed) to avoid colliding with
/// the retired `RAGpackManagerView` in `Shared/ContentView.swift`, which is
/// still compiled into the macOS target.
private struct DesktopRAGpackManagerView: View {
    @ObservedObject var documentManager: DocumentManager
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage RAGpacks").font(.headline)
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    Label("Import .zip", systemImage: "plus")
                }
                Button("Done") { dismiss() }
            }
            .padding(12)

            Divider()

            if documentManager.ragpackChunks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No RAGpacks imported yet.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(documentManager.ragpackChunks.keys.sorted(), id: \.self) { key in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key).font(.system(size: 14, weight: .medium))
                                Text("Chunks: \(documentManager.ragpackChunks[key]?.count ?? 0)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                documentManager.deleteRAGpack(named: key)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.zip]) { result in
            if case let .success(url) = result {
                documentManager.importDocument(file: url)
            }
        }
        // ADR-0011 §4: surface RAGpack import failures instead of failing silently.
        .alert(
            "RAGpack Import Failed",
            isPresented: Binding(
                get: { documentManager.lastImportError != nil },
                set: { if !$0 { documentManager.lastImportError = nil } }
            ),
            presenting: documentManager.lastImportError
        ) { _ in
            Button("OK", role: .cancel) { documentManager.lastImportError = nil }
        } message: { error in
            Text(error.errorDescription ?? "The RAGpack could not be imported.")
        }
    }
}

#Preview {
    DesktopSettingsView(documentManager: DocumentManager())
        .environmentObject(AppSettings.shared)
        .frame(width: 600, height: 700)
}
#endif
