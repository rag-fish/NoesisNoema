//
//  MinimalClientView.swift
//  NoesisNoema
//
//  X-1 Minimal Client Interface
//  Implements explicit human-driven interaction without autonomous behavior
//

import SwiftUI

/// Minimal client interface view model
/// Handles explicit user intent with no background execution
@MainActor
class MinimalClientViewModel: ObservableObject {
    @Published var prompt: String = ""
    @Published var response: String = ""
    @Published var isProcessing: Bool = false

    // EPIC1 Phase 4-A: ExecutionCoordinator injected via dependency
    private var executionCoordinator: ExecutionCoordinating

    init(executionCoordinator: ExecutionCoordinating) {
        self.executionCoordinator = executionCoordinator
    }

    // Allow updating coordinator from environment
    func setCoordinator(_ coordinator: ExecutionCoordinating) {
        self.executionCoordinator = coordinator
    }

    /// Explicit submit action - user-initiated only
    /// Routing: User → submit() → ExecutionCoordinator (invocation boundary)
    func submit() async {
        guard !prompt.isEmpty else { return }
        guard !isProcessing else { return }

        isProcessing = true
        response = ""

        let userPrompt = prompt

        // Phase 4-A: Route through ExecutionCoordinator
        // ExecutionCoordinator delegates to ModelManager (preserves current behavior)
        // Router + PolicyEngine integration deferred to Phase 5
        do {
            let request = NoemaRequest(query: userPrompt)
            let result = try await executionCoordinator.execute(request: request)
            response = result.text
        } catch {
            response = "Error: \(error.localizedDescription)"
        }

        prompt = ""
        isProcessing = false
    }
}

/// X-1 Minimal Client Interface
/// Cross-platform SwiftUI view with explicit user control
struct MinimalClientView: View {
    @EnvironmentObject private var executionCoordinator: ExecutionCoordinator
    @StateObject private var viewModel: MinimalClientViewModel

    init() {
        // Initialize with temporary coordinator (will be replaced by environment object)
        _viewModel = StateObject(wrappedValue: MinimalClientViewModel(
            executionCoordinator: ExecutionCoordinator()
        ))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Minimal Client Interface")
                .font(.title)
                .padding(.top)

            // Text input for prompt
            #if os(macOS)
            TextEditor(text: $viewModel.prompt)
                .font(.body)
                .frame(minHeight: 100)
                .border(Color.secondary.opacity(0.3), width: 1)
                .padding(.horizontal)
                .disabled(viewModel.isProcessing)
            #else
            TextEditor(text: $viewModel.prompt)
                .font(.body)
                .frame(minHeight: 100)
                .border(Color.secondary.opacity(0.3), width: 1)
                .padding(.horizontal)
                .disabled(viewModel.isProcessing)
            #endif

            // Explicit submit button
            Button(action: {
                Task {
                    await viewModel.submit()
                }
            }) {
                if viewModel.isProcessing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Processing...")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Submit")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.prompt.isEmpty || viewModel.isProcessing)
            .padding(.horizontal)

            // Response display
            ScrollView {
                Text(viewModel.response)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.1))
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .onAppear {
            // Update ViewModel with injected ExecutionCoordinator from environment
            viewModel.setCoordinator(executionCoordinator)
        }
    }
}

#Preview {
    MinimalClientView()
}
