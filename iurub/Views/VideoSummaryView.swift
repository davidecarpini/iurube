import SwiftUI

struct VideoSummaryView: View {
    let video: SavedVideo
    @EnvironmentObject private var summaries: SummaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showingCredentials = false
    @State private var confirmingReset = false
    @FocusState private var inputFocused: Bool

    private var messages: [SummaryMessage] { summaries.conversations[video.id] ?? [] }
    private var isBusy: Bool { summaries.busy.contains(video.id) }
    private var pendingQuestion: String { summaries.pending[video.id] ?? "" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                videoHeader
                conversation
                composer
            }
            .background(Theme.canvas)
            .navigationTitle("Riassunto")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .appLeading) {
                    Menu {
                        Button("Chiave OpenRouter", systemImage: "key") { showingCredentials = true }
                        Button("Nuova conversazione", systemImage: "arrow.counterclockwise", role: .destructive) {
                            confirmingReset = true
                        }.disabled(isBusy || messages.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Opzioni del riassunto")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { inputFocused = false; dismiss() }
                        .accessibilityIdentifier("closeSummary")
                }
            }
            .alert("Iniziare una nuova conversazione?", isPresented: $confirmingReset) {
                Button("Annulla", role: .cancel) {}
                Button("Ricomincia", role: .destructive) {
                    summaries.clear(videoID: video.id)
                    summaries.request(video: video)
                }
            } message: { Text("La chat di questo video verrà sostituita con un nuovo riassunto.") }
            .sheet(isPresented: $showingCredentials) { OpenRouterCredentialsView() }
            .task {
                if messages.isEmpty && summaries.pending[video.id] == nil && summaries.errors[video.id] == nil {
                    summaries.request(video: video)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var videoHeader: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "play.rectangle.fill")
                .font(.title3).foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 5) {
                Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(video.channel.isEmpty ? "Gemini · Video YouTube" : "\(video.channel) · Gemini")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(messages) { message in messageBubble(message).id(message.id) }
                    if !pendingQuestion.isEmpty {
                        HStack {
                            Spacer(minLength: 36)
                            Text(pendingQuestion).font(.body)
                                .padding(15)
                                .foregroundStyle(.primary)
                                .background(Theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    if isBusy {
                        HStack(spacing: 12) {
                            ProgressView().tint(Theme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(messages.isEmpty ? "Sto analizzando il video…" : "Sto preparando la risposta…")
                                    .font(.subheadline.weight(.medium))
                                if messages.isEmpty {
                                    Text("Puoi chiudere questa chat e tornare qui.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityIdentifier("summaryLoading")
                    }
                    if let error = summaries.errors[video.id] {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Riprova", systemImage: "arrow.clockwise") {
                                summaries.request(video: video, question: pendingQuestion.isEmpty ? nil : pendingQuestion)
                            }
                            .buttonStyle(.bordered).accessibilityIdentifier("summaryRetry")
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if let error = summaries.persistenceError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                    if !messages.isEmpty && !isBusy && summaries.errors[video.id] == nil {
                        suggestions
                    }
                    Color.clear.frame(height: 1).id("latest")
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("summaryConversation")
            .transaction { transaction in
                if #available(iOS 18, macOS 15, *) {
                    transaction.scrollContentOffsetAdjustmentBehavior = .disabled
                }
            }
            // Only conversation events move the reader; keyboard and composer resizing must not.
            .onChange(of: messages.count) { _, _ in scrollToLatest(proxy) }
            .onChange(of: isBusy) { _, _ in scrollToLatest(proxy) }
            .onAppear { scrollToLatest(proxy) }
        }
    }

    private func messageBubble(_ message: SummaryMessage) -> some View {
        let isUser = message.role == "user"
        return HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 9) {
                if !isUser {
                    Label(message.id == messages.first?.id ? "Il video, in breve" : "Gemini", systemImage: "sparkles")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                Text(markdown(message.text))
                    .font(.body).lineSpacing(4).textSelection(.enabled)
                    .accessibilityIdentifier(isUser ? "summaryQuestion" : "summaryReply")
                if !isUser {
                    let name = message.modelID.flatMap(SummaryModel.init(rawValue:))?.name ?? SummaryModel.flash25.name
                    Text(message.costUSD.map { name + " · " + $0.formatted(.currency(code: "USD").precision(.fractionLength(2...6))) } ?? name)
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("summaryReplyModel")
                }
            }
            .padding(16)
            .frame(maxWidth: isUser ? nil : .infinity, alignment: .leading)
            .background(isUser ? Theme.accent.opacity(0.13) : Theme.card, in: RoundedRectangle(cornerRadius: 20))
            if !isUser { Spacer(minLength: 10) }
        }
    }

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["Spiegamelo semplice", "Cosa posso applicare?", "Approfondisci i punti chiave"], id: \.self) { question in
                    Button(question) { send(question) }
                        .font(.caption.weight(.medium)).padding(.horizontal, 13).padding(.vertical, 12)
                        .background(Theme.card, in: Capsule())
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 9) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Chiedi qualcosa sul video…", text: $draft, axis: .vertical)
                    .lineLimit(1...5).padding(.horizontal, 15).padding(.vertical, 12)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 23))
                    .focused($inputFocused).submitLabel(.send)
                    .accessibilityIdentifier("summaryInput")
                    .onSubmit { send(draft) }
                    .onChange(of: draft) { _, value in if value.count > 4_000 { draft = String(value.prefix(4_000)) } }
                if isBusy {
                    Button { summaries.cancel(videoID: video.id) } label: {
                        Image(systemName: "stop.fill").font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .accessibilityLabel("Interrompi risposta").accessibilityIdentifier("cancelSummary")
                } else {
                    Button { send(draft) } label: {
                        Image(systemName: "arrow.up").font(.headline)
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(Theme.accent, in: Circle())
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || messages.isEmpty)
                    .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || messages.isEmpty ? 0.4 : 1)
                    .accessibilityLabel("Invia domanda").accessibilityIdentifier("sendSummaryQuestion")
                }
            }
            Text("Le risposte si basano sul video. La chat resta su questo dispositivo.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .background(Theme.card)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy, !messages.isEmpty else { return }
        draft = ""
        inputFocused = false
        summaries.request(video: video, question: question)
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        // A new summary already begins at the top. Setting an explicit target
        // here lets the scroll view re-anchor that message when its height changes.
        guard !messages.isEmpty, messages.count > 1 || !pendingQuestion.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("latest", anchor: .bottom)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        // SwiftUI Text renders inline emphasis, but does not lay out Markdown
        // headings or lists. Normalize those markers without losing paragraph breaks.
        var insideCodeFence = false
        let normalized = text.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideCodeFence.toggle()
                return line
            }
            guard !insideCodeFence else { return line }
            if let marker = line.range(of: #"^[ \t]{0,3}#{1,6}[ \t]+"#, options: .regularExpression) {
                var heading = String(line[marker.upperBound...])
                    .replacingOccurrences(of: #"[ \t]+#+[ \t]*$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if heading.hasPrefix("**"), heading.hasSuffix("**"), heading.count >= 4 {
                    heading = String(heading.dropFirst(2).dropLast(2))
                }
                return "**\(heading)**"
            }
            return line.replacingOccurrences(of: #"^([ \t]*)[-*+][ \t]+"#, with: "$1• ", options: .regularExpression)
        }.joined(separator: "\n")
        return (try? AttributedString(markdown: normalized, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(normalized)
    }
}
