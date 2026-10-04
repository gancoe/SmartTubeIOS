import FirebaseCore
import FirebaseCrashlytics
import SmartTubeIOS
import SmartTubeIOSCore
import SwiftUI

/// tvOS entry point for SmartTube.
/// The device-code + QR sign-in flow is natively designed for Apple TV —
/// the user reads a code on screen and activates on their phone at yt.be/activate.
@main
struct SmartTubeTVApp: App {
    // Declared without default values so that init() can call FirebaseApp.configure()
    // before any of these objects are instantiated.
    @State private var api: InnerTubeAPI
    @State private var authService: AuthService
    @State private var browseViewModel: BrowseViewModel
    @State private var settingsStore: SettingsStore
    /// Shared download service — required by RootView and VideoCardView even on
    /// tvOS (where downloads are disabled in UI). Must be present in the environment
    /// or SwiftUI throws a fatal "No Observable object of type VideoDownloadService"
    /// error at launch.
    @State private var cardDownloadService: VideoDownloadService

    init() {
        // #92: see AppEntry.swift's init() for why order matters here — settingsStore
        // must exist before deciding whether to configure Firebase at all.
        let settingsStore = SettingsStore()
        CrashlyticsLogger.isEnabled =
            !settingsStore.settings.disableAnalytics
            && Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
        if CrashlyticsLogger.isEnabled {
            FirebaseApp.configure()
        }
        let poTokenProvider: (any PoTokenProvider)? = {
            if let url = settingsStore.settings.poTokenServiceURL {
                return ServerPoTokenProvider(serviceURL: url)
            }
            return BotGuardClient()
        }()
        let api = InnerTubeAPI(authToken: nil, poTokenProvider: poTokenProvider)
        _api = State(initialValue: api)
        _authService = State(initialValue: AuthService())
        _browseViewModel = State(initialValue: BrowseViewModel(api: api))
        _settingsStore = State(initialValue: settingsStore)
        _cardDownloadService = State(initialValue: VideoDownloadService(api: api))
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .environment(authService)
                .environment(browseViewModel)
                .environment(settingsStore)
                .environment(\.innerTubeAPI, api)
                .environment(cardDownloadService)
                .onChange(of: authService.accessToken, initial: true) { _, newToken in
                    Task {
                        await api.setAuthToken(newToken)
                        await browseViewModel.updateAuthToken(newToken)
                    }
                }
                .onChange(of: authService.sapisid, initial: true) { _, newSapisid in
                    Task { await api.setSAPISID(newSapisid) }
                }
                .onChange(of: settingsStore.settings.enabledSections) { _, newSections in
                    browseViewModel.configureSections(newSections)
                }
                .onChange(of: settingsStore.settings.historyState, initial: true) { _, newState in
                    browseViewModel.updateHistoryEnabled(newState == .enabled)
                }
        }
    }

    @ViewBuilder private var rootContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting-player-ui"),
            let argument = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("--uitesting-deeplink-video=")
            })
        {
            let id = String(argument.dropFirst("--uitesting-deeplink-video=".count))
            TVPlayerUITestHost(
                video: Video(
                    id: id, title: id, channelTitle: "Test Channel",
                    channelId: ProcessInfo.processInfo.arguments.contains("--uitesting-channel-content")
                        ? "UCNativePlayerTest" : nil,
                    description: "Test video description"
                ),
                api: api
            )
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}

#if DEBUG
private struct TVPlayerUITestHost: View {
    let video: Video
    let api: InnerTubeAPI
    @State private var selectedVideo: Video?
    @FocusState private var openFocused: Bool
    @Namespace private var focusNamespace

    var body: some View {
        TabView {
            NavigationStack {
                Button("Open test video") { selectedVideo = video }
                    .focused($openFocused)
                    .prefersDefaultFocus(in: focusNamespace)
                    .navigationDestination(item: $selectedVideo) { selected in
                        PlayerView(video: selected, api: api)
                    }
            }
            .focusScope(focusNamespace)
            .defaultFocus($openFocused, true)
            .task {
                try? await Task.sleep(for: .milliseconds(50))
                openFocused = true
            }
            .tabItem { Text("Player test") }
        }
    }
}
#endif
