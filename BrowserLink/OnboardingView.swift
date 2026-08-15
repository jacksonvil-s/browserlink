import SwiftUI

/// The three steps of first-run onboarding, in display order.
/// Add cases here (and a matching case in `OnboardingView`'s step switch)
/// to extend the flow later — progress dots, back/continue wiring, and
/// completion persistence all adapt automatically.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case introduction
    case settings
}

/// First-run onboarding flow: welcomes the user, briefly explains what the
/// app does, then lets them pick a few starting preferences before landing
/// in the normal menu bar experience.
///
/// Presented by AppDelegate (see `presentOnboarding()`) either at first
/// launch — when `AppSettings.shared.hasCompletedOnboarding` is false — or
/// on demand from Preferences → "Restart onboarding".
///
/// Visual language deliberately matches ChooserPanelView (translucent glass
/// card, accent-tinted wash, rounded corners) rather than the flat
/// Preferences window, since this is meant to feel like a welcoming first
/// moment rather than a settings screen.
struct OnboardingView: View {
    /// Called when the user completes the flow. AppDelegate uses this to
    /// close the window and set `hasCompletedOnboarding = true`.
    let onFinish: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var step: OnboardingStep = .welcome
    @State private var hasAppeared = false

    /// Which edge the next/previous step should slide in from — set right
    /// before `step` changes so the transition direction always matches
    /// Continue (forward) vs Back (backward).
    @State private var transitionEdge: Edge = .trailing

    var body: some View {
        VStack(spacing: 0) {
            // Welcome is short and fixed, so it's centered directly rather
            // than scrolled. Introduction/Settings can grow (more features,
            // more toggles) so they're wrapped in a ScrollView as a
            // permanent safety net against content ever being cut off.
            Group {
                switch step {
                case .welcome:
                    welcomeStep
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(36)
                case .introduction:
                    ScrollView {
                        introductionStep
                            .padding(36)
                    }
                case .settings:
                    ScrollView {
                        settingsStep
                            .padding(36)
                    }
                }
            }
            .id(step)
            .transition(
                .asymmetric(
                    insertion: .move(edge: transitionEdge).combined(with: .opacity),
                    removal: .move(edge: transitionEdge == .trailing ? .leading : .trailing).combined(with: .opacity)
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider().opacity(0.15)
            footer
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 560, idealHeight: 620)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(settings.tintColor.opacity(0.06))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .scaleEffect(hasAppeared ? 1 : 0.94)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(settings.tintColor.gradient)
                    .frame(width: 84, height: 84)
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text("Welcome to BrowserLink")
                .font(.system(size: 24, weight: .semibold))
            Text("Let's get you set up. This will only take a moment.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - Introduction

    private var introductionStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What BrowserLink does")
                .font(.system(size: 20, weight: .semibold))

            // TODO: fill in the real feature set/copy here. Placeholders
            // below follow the app's actual behavior as a starting point.
            featureRow(
                icon: "hand.tap.fill",
                title: "Choose where links open",
                detail: "Click any link, anywhere, and pick which browser opens it."
            )
            featureRow(
                icon: "eye.fill",
                title: "Quick Preview",
                detail: "Peek at a link instantly without committing to a full browser tab. All cookies and things destroyed after."
            )
            featureRow(
                icon: "shield.fill",
                title: "Suspicious link warnings",
                detail: "Local, on-device checks flag common phishing patterns before you click through."
            )
            featureRow(
                icon: "figure.walk.motion",
                title: "Auto detection",
                detail: "We auto detect your installed browsers. As simple as that."
            )
            featureRow(
                icon: "chevron.left.forwardslash.chevron.right",
                title: "Open source",
                detail: "Completely open source on Github. Check the About tab in settings for more info."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(settings.tintColor.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(settings.tintColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Settings

    private var settingsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("A few starting preferences")
                    .font(.system(size: 20, weight: .semibold))
                Text("You can change any of these later in Preferences. There are even more customisation options in preferences!")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            OnboardingCard(title: "Startup") {
                onboardingToggleRow(
                    title: "Launch at Login",
                    isOn: $settings.launchAtLoginEnabled
                )
            }

            OnboardingCard(title: "Chooser") {
                onboardingToggleRow(
                    title: "Show Site Icons in Chooser",
                    subtitle: "Fetched from Google's favicon service. You can switch it off if you have privacy concerns.",
                    isOn: $settings.showFaviconsInChooser
                )
                Divider().opacity(0.5).padding(.leading, 14)
                onboardingToggleRow(
                    title: "Enable Quick Preview Window",
                    subtitle: "Disable if you want a pure browser picker.",
                    isOn: $settings.enablePreviewWindow
                )
                Divider().opacity(0.5).padding(.leading, 14)
                onboardingToggleRow(
                    title: "Play Sound When Chooser Appears",
                    isOn: $settings.playSoundOnChooserAppear
                )
            }

            OnboardingCard(title: "Security") {
                onboardingToggleRow(
                    title: "Warn About Suspicious Links",
                    subtitle: "We recommend that you keep this option on to protect yourself against malicious links. This process runs entirely on device, but this is not a catch all. Not to be a replacement for a high vigilance while surfing the web.",
                    isOn: $settings.warnAboutSuspiciousLinks
                )
            }
            
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A rounded, grouped container with a small-caps header — same visual
    /// recipe as PreferencesView's SettingsCard, kept as a local duplicate
    /// here since that one is private to PreferencesView.swift and this
    /// view is meant to stay self-contained.
    private struct OnboardingCard<Content: View>: View {
        let title: String
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    content
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.background.secondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private func onboardingToggleRow(title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Footer / navigation

    private var footer: some View {
        HStack {
            progressDots

            Spacer()

            if step != .welcome {
                Button("Back") { goTo(step: previousStep) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }

            Button(isLastStep ? "Get Started" : "Continue") {
                if isLastStep {
                    onFinish()
                } else {
                    goTo(step: nextStep)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { candidate in
                Capsule()
                    .fill(candidate == step ? settings.tintColor : Color.secondary.opacity(0.25))
                    .frame(width: candidate == step ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: step)
    }

    private var isLastStep: Bool {
        step.rawValue == OnboardingStep.allCases.count - 1
    }

    private var nextStep: OnboardingStep {
        OnboardingStep(rawValue: step.rawValue + 1) ?? step
    }

    private var previousStep: OnboardingStep {
        OnboardingStep(rawValue: step.rawValue - 1) ?? step
    }

    private func goTo(step newStep: OnboardingStep) {
        transitionEdge = newStep.rawValue > step.rawValue ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.25)) {
            step = newStep
        }
    }
}
