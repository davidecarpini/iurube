import SwiftUI

struct BrandLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false
    var label = "Caricamento"

    var body: some View {
        ZStack {
            Circle().stroke(Theme.accent.opacity(0.12), lineWidth: 2)
            Circle().trim(from: 0.08, to: 0.45).stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(turning && !reduceMotion ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 1.15).repeatForever(autoreverses: false), value: turning)
            Image("EntryMark").resizable().frame(width: 32, height: 32)
        }
        .frame(width: 54, height: 54)
        .padding(9).background(.regularMaterial, in: Circle())
        .onAppear { turning = true }
        .accessibilityElement(children: .ignore).accessibilityLabel(label)
        .accessibilityIdentifier("brandLoader")
        .allowsHitTesting(false)
    }
}

struct WelcomeView: View {
    var signIn: () -> Void
    var explore: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 0) {
                brand
                Spacer(minLength: 28)
                introduction
                Spacer(minLength: 28)
                actions
            }
            ScrollView { VStack(alignment: .leading, spacing: 30) { brand; introduction; actions } }
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .frame(maxWidth: 500, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }

    private var brand: some View {
        Text("iurub").font(.system(.title2, design: .rounded, weight: .bold))
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(Theme.accent.opacity(0.12))
                    .rotationEffect(.degrees(-10)).offset(x: -4)
                Image("EntryMark").resizable().rotationEffect(.degrees(2))
            }
            .frame(width: 88, height: 88).padding(.bottom, 8).accessibilityHidden(true)
            Text("Ritrova i tuoi video.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Accedi a YouTube per aprire la tua lista Guarda più tardi, seguire le iscrizioni e riprendere da dove eri rimasto.")
                .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: signIn) {
                HStack { Text("Accedi a YouTube"); Spacer(); Image(systemName: "arrow.right") }
                    .font(.headline).padding(.horizontal, 20).padding(.vertical, 16)
                    .foregroundStyle(.white).background(Color(red: 0.70, green: 0.20, blue: 0.15), in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain).accessibilityIdentifier("welcomeSignIn")
            Button("Esplora senza accedere", action: explore)
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 48).accessibilityIdentifier("welcomeExplore")
        }
    }
}

struct YouTubeSignInView: View {
    @StateObject private var session = BrowserSession(startPage: .watchLater, role: .signIn)
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var completed: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                    Text(session.pageHost.isEmpty ? "YouTube" : session.pageHost)
                }
                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                Divider()
                ZStack {
                    YouTubeWebView(session: session)
                    if let error = session.loadError {
                        ContentUnavailableView {
                            Label("Accesso da verificare", systemImage: "person.crop.circle.badge.exclamationmark")
                        } description: {
                            Text(error)
                        } actions: {
                            Button(session.checkingSignIn ? "Verifica in corso…" : "Riprova", action: session.retrySignIn)
                                .buttonStyle(.borderedProminent).disabled(session.checkingSignIn)
                                .accessibilityIdentifier("retrySignIn")
                        }.background(Theme.background)
                    }
                }
            }
            .navigationTitle("Accedi a YouTube").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }.accessibilityIdentifier("closeSignIn")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Ricomincia", action: session.startSignIn)
                        Button("Verifica accesso", action: session.verifySignIn)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Opzioni di accesso")
                }
            }
        }
        .task {
            if !session.hasLoaded { session.startSignIn() }
            // Google may leave the form visible after accepting the account.
            // Poll the shared session without navigating the form under the user.
            var interval = 5
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                if scenePhase == .active { session.verifySignIn() }
                interval = min(interval * 2, 30)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && session.hasLoaded { session.verifySignIn() }
        }
        .onDisappear { session.cancelSignInCheck() }
        .onReceive(session.$signedIn) { signed in if signed == true { completed() } }
    }
}
