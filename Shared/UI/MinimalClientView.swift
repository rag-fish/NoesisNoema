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

    /// Explicit submit action - user-initiated only
    /// Routing: User → submit() → ModelManager (invocation boundary)
    func submit() async {
        guard !prompt.isEmpty else { return }
        guard !isProcessing else { return }

        isProcessing = true
        response = ""

        let userPrompt = prompt

        // Invocation boundary: call through ModelManager
        let result = await Task.detached(priority: .userInitiated) {
            await ModelManager.shared.generateAsyncAnswer(question: userPrompt)
        }.value

        response = result
        prompt = ""
        isProcessing = false
    }
}

/// X-1 Minimal Client Interface
/// Cross-platform SwiftUI view with explicit user control
struct MinimalClientView: View {
    @StateObject private var viewModel = MinimalClientViewModel()

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
    }
}

#Preview {
    MinimalClientView()
}
