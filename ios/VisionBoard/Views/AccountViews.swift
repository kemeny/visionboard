import AuthenticationServices
import SwiftUI

// Settings > Account. Optional: signing in backs up the list of boards so a
// new iPhone can bring them back. Signed in, it offers Back Up Now, Sign Out
// and Delete Account (App Store Guideline 5.1.1(v)).
struct AccountSection: View {
    @Environment(AccountService.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmDelete = false
    @State private var loggedPrompt = false

    var body: some View {
        if account.isAvailable {
            Group {
                if account.isSignedIn {
                    signedIn
                } else {
                    signedOut
                }
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) {
                    Task { await account.deleteAccount(deleteCloudBoards: false) }
                }
                Button("Delete Account and Cloud Boards", role: .destructive) {
                    Task { await account.deleteAccount(deleteCloudBoards: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your account and the backup of your board list are deleted from our server. You can also delete every board's cloud copy, which stops sync on your other devices. Your boards stay on this iPhone either way.")
            }
        }
    }

    private var signedOut: some View {
        let fresh = account.looksFresh
        return Section {
            SignInWithAppleButton(
                fresh ? .continue : .signIn,
                onRequest: { request in
                    request.requestedScopes = [.email]
                    request.nonce = account.prepareNonce()
                },
                onCompletion: { result in Task { await account.handle(result) } }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 44)
            .disabled(account.busy)
            statusRows
        } header: {
            fresh ? Text("Restore from Your Apple Account") : Text("Account")
        } footer: {
            fresh
                ? Text("Used VisionBoard on another iPhone? Sign in with the same Apple Account to bring your boards back.")
                : Text("Optional. Signing in turns on sync for every board and backs up the list of your boards, so a new iPhone can bring them back. Everything works the same without an account.")
        }
        .onAppear {
            guard !loggedPrompt else { return }
            loggedPrompt = true
            Analytics.capture("signin_prompt_viewed", ["source": fresh ? "settings_restore" : "settings"])
        }
    }

    @ViewBuilder
    private var signedIn: some View {
        Section {
            LabeledContent("Apple Account") {
                if let email = account.email {
                    Text(email)
                } else {
                    Text("Signed In")
                }
            }
            if let last = account.lastBackup {
                LabeledContent("Last Backup") {
                    Text(last.formatted(.relative(presentation: .named)))
                }
            }
            Button("Back Up Now", systemImage: "arrow.up.circle") {
                Task { await account.backUpNow() }
            }
            .disabled(account.busy)
            Button("Restore Boards", systemImage: "arrow.down.circle") {
                Task { await account.restoreNow() }
            }
            .disabled(account.busy)
            statusRows
            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                account.signOut()
            }
            .disabled(account.busy)
        } header: {
            Text("Account")
        } footer: {
            Text("Every board syncs, and the list of your boards is backed up to your account. Signing out keeps your boards and their sync on this iPhone.")
        }
        Section {
            Button("Delete Account", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                confirmDelete = true
            }
            .disabled(account.busy)
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        if account.busy {
            HStack(spacing: 8) {
                ProgressView()
                Text("Working…")
                    .foregroundStyle(.secondary)
            }
        }
        if let error = account.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.callout)
        }
        if let notice = account.notice {
            Label(notice, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.callout)
        }
    }
}

// A one-time nudge on the board once it has a few things on it. Tapping
// either button hides it for good.
struct BackupBanner: View {
    @Environment(AccountService.self) private var account
    @Environment(BoardStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage("backup-banner-dismissed") private var dismissed = false
    @State private var logged = false

    static let minimumItems = 5

    var body: some View {
        if !dismissed, account.isAvailable, !account.isSignedIn, store.items.count >= Self.minimumItems {
            HStack(spacing: 12) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Back up your board with Apple")
                        .font(.subheadline.weight(.semibold))
                    Text("Keep your boards if you change phones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Set Up") {
                    dismissed = true
                    router.tab = .settings
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                guard !logged else { return }
                logged = true
                Analytics.capture("signin_prompt_viewed", ["source": "board_banner"])
            }
        }
    }
}
