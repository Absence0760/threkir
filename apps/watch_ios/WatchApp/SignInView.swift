import SwiftUI

/// Email + password on the wrist, for a watch with no session of its own.
///
/// The affordance is watchOS's own text-entry sheet — tapping either field
/// raises it, and the runner picks dictation, Scribble or the QWERTY keyboard
/// from there. That is the platform's answer to the problem Wear OS solves
/// with an inline `BasicTextField` + IME, and it is the only one on watchOS:
/// there is no in-app keyboard to embed.
///
/// Nobody should be typing a password here routinely — the ordinary path is
/// still the paired iPhone. This exists for the watch that is away from it.
struct SignInView: View {
    @ObservedObject var auth: WatchAuth
    let onDone: () -> Void

    @State private var email = ""
    @State private var password = ""

    private var canSubmit: Bool {
        auth.isConfigured && !auth.isBusy
            && !WatchAuthRequest.normalize(email: email).isEmpty && !password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Sign in")
                    .font(.headline)

                if let session = auth.session {
                    signedIn(email: session.email)
                } else if auth.isConfigured {
                    form
                }

                if let fault = auth.fault {
                    Text(fault.message)
                        .font(.caption2)
                        .foregroundColor(AppTheme.error)
                        .multilineTextAlignment(.center)
                } else if !auth.isConfigured {
                    Text(WatchAuthFault.notConfigured.message)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var form: some View {
        VStack(spacing: 8) {
            TextField("Email", text: $email)
            SecureField("Password", text: $password)

            Button {
                let submitted = (email, password)
                // Cleared before the request, not after: the field is the
                // only place the password still exists on this watch, and a
                // sheet left open on a failed attempt should not be holding
                // it for whoever picks the wrist up next.
                password = ""
                Task {
                    await auth.signIn(email: submitted.0, password: submitted.1)
                    if auth.session != nil { onDone() }
                }
            } label: {
                if auth.isBusy {
                    ProgressView()
                } else {
                    Text("Sign in")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.coralDeep)
            .disabled(!canSubmit)
            .accessibilityHint("Signs this watch in with the email and password above")
        }
    }

    private func signedIn(email: String) -> some View {
        VStack(spacing: 6) {
            Text("Signed in")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(verbatim: email)
                .font(.caption)
                .foregroundColor(AppTheme.lilac)
                .multilineTextAlignment(.center)

            // No confirmation: signing out deletes this watch's copy of a
            // session and nothing else — no run, no track, no queued transfer
            // — and signing back in restores it, so by
            // `docs/architecture/conventions.md` § Destructive actions it
            // earns no dialog. Wear OS's sign-out is an unguarded tap for the
            // same reason.
            Button("Sign out") {
                auth.signOut()
                onDone()
            }
            .font(.caption)
            .accessibilityHint("Deletes this watch's saved session and signs it out")
        }
    }
}
