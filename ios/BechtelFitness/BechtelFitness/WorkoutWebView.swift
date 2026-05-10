import SwiftUI
import WebKit

enum WorkoutNativeStorage {
    private static let trackedKeys = [
        "bf5_s",
        "bf5_l",
        "bf5_sc",
        "bf5_cf_week",
        "bf5_cf_logs"
    ]
    private static let mirrorPrefix = "bf.native.mirror."

    static func snapshot() -> [String: String] {
        trackedKeys.reduce(into: [String: String]()) { result, key in
            if let value = UserDefaults.standard.string(forKey: mirrorKey(for: key)) {
                result[key] = value
            }
        }
    }

    static func save(key: String, value: String?) {
        guard trackedKeys.contains(key) else { return }

        let storageKey = mirrorKey(for: key)
        if let value {
            UserDefaults.standard.set(value, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    private static func mirrorKey(for key: String) -> String {
        mirrorPrefix + key
    }

    static func activeScreen() -> WorkoutSection {
        guard
            let rawValue = UserDefaults.standard.string(forKey: mirrorKey(for: "bf5_sc")),
            let data = rawValue.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(String.self, from: data),
            let screen = WorkoutSection(rawValue: decoded)
        else {
            return .home
        }

        return screen
    }
}

enum AppSection: CaseIterable, Identifiable, Equatable, Hashable {
    case home
    case today
    case history
    case crossfit
    case plan
    case health

    var id: String { title }

    var title: String {
        switch self {
        case .home:
            "Home"
        case .today:
            "Workout"
        case .history:
            "Progress"
        case .crossfit:
            "WOD"
        case .plan:
            "Program"
        case .health:
            "Health"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .today:
            "figure.strengthtraining.traditional"
        case .history:
            "chart.line.uptrend.xyaxis"
        case .crossfit:
            "flame.fill"
        case .plan:
            "calendar"
        case .health:
            "heart.text.square.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .home:
            "Overview, streaks, and your next training session."
        case .today:
            "Live workout logging with your existing program rules."
        case .history:
            "Progress, past sessions, and workout trends."
        case .crossfit:
            "Conditioning, scores, notes, and daily WOD tracking."
        case .plan:
            "Your phase structure, schedule, and program layout."
        case .health:
            "Recovery, readiness, and daily biometric context."
        }
    }

    var workoutSection: WorkoutSection? {
        switch self {
        case .home:
            .home
        case .today:
            .today
        case .history:
            .history
        case .crossfit:
            .crossfit
        case .plan:
            .plan
        case .health:
            nil
        }
    }
}

enum WorkoutSection: String, CaseIterable, Identifiable {
    case home
    case today
    case history
    case crossfit
    case plan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Home"
        case .today:
            "Workout"
        case .history:
            "Progress"
        case .crossfit:
            "WOD"
        case .plan:
            "Program"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .today:
            "figure.strengthtraining.traditional"
        case .history:
            "chart.line.uptrend.xyaxis"
        case .crossfit:
            "flame.fill"
        case .plan:
            "calendar"
        }
    }
}

struct WorkoutWebView: View {
    @StateObject private var browser = WorkoutBrowserModel()
    @State private var selectedTab: AppSection = .home
    @State private var showingLiveWorkout = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer
                    .ignoresSafeArea()

                WorkoutBrowser(model: browser)
                    .opacity(showingLiveWorkout ? 1 : 0)
                    .allowsHitTesting(showingLiveWorkout)

                if !showingLiveWorkout {
                    TabView(selection: $selectedTab) {
                        tabContent(for: .home)
                            .tabItem { Label("Home", systemImage: AppSection.home.systemImage) }
                            .tag(AppSection.home)
                            .accessibilityLabel("Home tab")
                            .accessibilityHint("Shows your overview and today's quick start.")

                        tabContent(for: .today)
                            .tabItem { Label("Workout", systemImage: AppSection.today.systemImage) }
                            .tag(AppSection.today)
                            .accessibilityLabel("Workout tab")
                            .accessibilityHint("Shows today's workout and live workout start.")

                        tabContent(for: .plan)
                            .tabItem { Label("Program", systemImage: AppSection.plan.systemImage) }
                            .tag(AppSection.plan)
                            .accessibilityLabel("Program tab")
                            .accessibilityHint("Shows your program and WOD views.")

                        tabContent(for: .history)
                            .tabItem { Label("Progress", systemImage: AppSection.history.systemImage) }
                            .tag(AppSection.history)
                            .accessibilityLabel("Progress tab")
                            .accessibilityHint("Shows workout history and progress charts.")

                        tabContent(for: .health)
                            .tabItem { Label("Health", systemImage: AppSection.health.systemImage) }
                            .tag(AppSection.health)
                            .accessibilityLabel("Health tab")
                            .accessibilityHint("Shows recovery and health metrics.")
                    }
                    .tint(AppTheme.gold)
                    .transition(.opacity)
                }

                if browser.isLoading && !browser.hasLoadedContent && browser.snapshot == nil {
                    loadingOverlay
                        .transition(.opacity)
                }

                if let message = browser.errorMessage, browser.snapshot == nil {
                    errorState(message)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: browser.isLoading)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: browser.errorMessage)
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: selectedTab)
            .navigationTitle(showingLiveWorkout ? "Live Workout" : currentSection.title)
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .top, spacing: 0) {
                if browser.isLoading && browser.hasLoadedContent && !showingLiveWorkout {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(AppTheme.gold)
                        .padding(.horizontal, AppTheme.Spacing.l)
                        .padding(.bottom, AppTheme.Spacing.xs)
                }
            }
            .toolbarBackground(AppTheme.navy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if showingLiveWorkout {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            closeLiveWorkout()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            .onAppear {
                syncSelectedTab(selectedTab)
            }
            .onChange(of: selectedTab) { _, section in
                syncSelectedTab(section)
            }
        }
    }

    @ViewBuilder
    private func tabContent(for section: AppSection) -> some View {
        switch section {
        case .home:
            if let snapshot = browser.snapshot {
                NativeWorkoutHomeView(
                    snapshot: snapshot,
                    isRefreshing: browser.isLoading,
                    onOpenWorkout: openLiveWorkout,
                    onOpenProgram: { select(.plan) }
                )
            } else {
                WorkoutSnapshotLoadingView(title: "Home")
            }
        case .today:
            if let snapshot = browser.snapshot {
                NativeWorkoutTodayView(
                    snapshot: snapshot,
                    isRefreshing: browser.isLoading,
                    onOpenLiveWorkout: openLiveWorkout,
                    onOpenProgram: { select(.plan) }
                )
            } else {
                WorkoutSnapshotLoadingView(title: "Workout")
            }
        case .plan:
            if let snapshot = browser.snapshot {
                NativeProgramView(
                    snapshot: snapshot,
                    onOpenWorkout: { openLiveWorkout() },
                    onOpenProgramWorkout: { phaseID, phaseWeek in
                        browser.updateProgramProgress(phaseID: phaseID, phaseWeek: phaseWeek)
                        openLiveWorkout()
                    },
                    onUpdateProgramProgress: { phaseID, phaseWeek in
                        browser.updateProgramProgress(phaseID: phaseID, phaseWeek: phaseWeek)
                    },
                    onResetCrossfitWeek: { browser.resetCrossfitWeek() },
                    onOpenCrossfitSource: { browser.openCrossfitSource() },
                    onToggleCrossfitDone: { day, isDone in browser.setCrossfitDone(day: day, isDone: isDone) },
                    onUpdateCrossfitScore: { day, score in browser.updateCrossfitLog(day: day, patch: ["score": score]) },
                    onUpdateCrossfitNotes: { day, notes in browser.updateCrossfitLog(day: day, patch: ["notes": notes]) }
                )
            } else {
                WorkoutSnapshotLoadingView(title: "Program")
            }
        case .history:
            if let snapshot = browser.snapshot {
                NativeProgressView(
                    snapshot: snapshot,
                    onOpenWorkout: { select(.today) }
                )
            } else {
                WorkoutSnapshotLoadingView(title: "Progress")
            }
        case .health:
            HealthDashboardContent()
        case .crossfit:
            EmptyView()
        }
    }

    private var currentSection: AppSection {
        selectedTab
    }

    private var backgroundLayer: some View {
        Group {
            if selectedTab == .health {
                AppTheme.pageGradient
            } else if showingLiveWorkout {
                AppTheme.workoutCanvas
            } else {
                AppTheme.dashboardGradient
            }
        }
    }

    private func select(_ section: AppSection) {
        selectedTab = section
        syncSelectedTab(section)
    }

    private func syncSelectedTab(_ section: AppSection) {
        if section != .today {
            showingLiveWorkout = false
            browser.setNativeLiveMode(false)
        }
        if let workoutSection = section.workoutSection {
            browser.navigate(to: workoutSection)
            browser.requestSnapshot()
        }
    }

    private func openLiveWorkout() {
        selectedTab = .today
        browser.navigate(to: .today)
        browser.requestSnapshot()
        browser.setNativeLiveMode(true)
        showingLiveWorkout = true
    }

    private func closeLiveWorkout() {
        showingLiveWorkout = false
        browser.setNativeLiveMode(false)
        browser.requestSnapshot()
    }

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: AppTheme.Size.icon, height: AppTheme.Size.icon)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.chip))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

            ProgressView()
                .tint(AppTheme.gold)

            Text("Pulling your latest training data")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: 280)
        .padding(.horizontal, AppTheme.Spacing.l)
        .padding(.vertical, AppTheme.Spacing.m)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row))
        .shadow(color: .black.opacity(0.18), radius: AppTheme.Spacing.xl, y: AppTheme.Spacing.s)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(AppTheme.gold)

            Text("Can't reach training data")
                .font(.title3.weight(.bold))

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                browser.reload()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: 320)
        .background(.background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
        .shadow(color: .black.opacity(0.18), radius: AppTheme.Spacing.xxl, y: AppTheme.Spacing.m)
        .padding()
    }
}

final class WorkoutBrowserModel: ObservableObject {
    let homeURL = URL(string: "https://jeffb823.github.io/bechtel-fitness/")!
    private let cacheURL: URL

    @Published var isLoading = false
    @Published var hasLoadedContent = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var errorMessage: String?
    @Published var activeScreen: WorkoutSection = WorkoutNativeStorage.activeScreen()
    @Published var snapshot: WorkoutEngineSnapshot? {
        didSet {
            persistSnapshot(snapshot)
        }
    }

    weak var webView: WKWebView?
    private var pendingScreen: WorkoutSection?
    private var pendingProgramProgress: (phaseID: Int, phaseWeek: Int)?
    private var nativeLiveModeEnabled = false

    init(fileManager: FileManager = .default) {
        let supportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folderURL = supportURL.appendingPathComponent("BechtelFitness", isDirectory: true)
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        cacheURL = folderURL.appendingPathComponent("last-snapshot.json")

        let size = (try? fileManager.attributesOfItem(atPath: cacheURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= 200_000 else { return }
        guard let data = try? Data(contentsOf: cacheURL),
              let cachedSnapshot = try? JSONDecoder().decode(WorkoutEngineSnapshot.self, from: data)
        else {
            return
        }
        snapshot = cachedSnapshot
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        errorMessage = nil

        if let webView, webView.url != nil {
            webView.reload()
        } else {
            webView?.load(URLRequest(url: homeURL))
        }
    }

    func openInSafari() {
        UIApplication.shared.open(webView?.url ?? homeURL)
    }

    func openCrossfitSource() {
        guard let source = snapshot?.crossfitWeek?.sourceUrl,
              let sourceURL = URL(string: source)
        else {
            return
        }
        UIApplication.shared.open(sourceURL)
    }

    func navigate(to screen: WorkoutSection) {
        activeScreen = screen
        pendingScreen = screen
        guard let webView else { return }
        evaluateNavigation(on: webView, to: screen)
    }

    func syncActiveScreen(_ screen: WorkoutSection) {
        activeScreen = screen
        if pendingScreen == screen {
            pendingScreen = nil
        }
    }

    func applyPendingNavigationIfNeeded() {
        guard let pendingScreen, let webView else { return }
        evaluateNavigation(on: webView, to: pendingScreen)
    }

    func updateNavigationState(from webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func requestSnapshot() {
        webView?.evaluateJavaScript("window.__bfSendSnapshot && window.__bfSendSnapshot();")
    }

    func setNativeLiveMode(_ enabled: Bool) {
        nativeLiveModeEnabled = enabled
        applyNativePresentationMode()
    }

    func applyNativePresentationMode() {
        let flag = nativeLiveModeEnabled ? "true" : "false"
        webView?.evaluateJavaScript("window.__bfNativeSetLiveMode && window.__bfNativeSetLiveMode(\(flag));")
    }

    func updateProgramProgress(phaseID: Int, phaseWeek: Int) {
        let boundedWeek = min(max(phaseWeek, 1), 9)
        let resolvedPhaseID = snapshot?.phases.first(where: { $0.id == phaseID })?.id ?? snapshot?.phases.first?.id ?? phaseID
        pendingProgramProgress = (resolvedPhaseID, boundedWeek)
        applyOptimisticProgramProgress(phaseID: resolvedPhaseID, phaseWeek: boundedWeek)
        applyPendingProgramProgressUpdate()
    }

    func updateCrossfitLog(day: String, patch: [String: Any]) {
        guard let dayLiteral = jsonLiteral(day), let patchLiteral = jsonLiteral(patch) else { return }
        let script = "window.__bfNativeUpdateCrossfitLog && window.__bfNativeUpdateCrossfitLog(\(dayLiteral), \(patchLiteral));"
        webView?.evaluateJavaScript(script)
    }

    func setCrossfitDone(day: String, isDone: Bool) {
        updateCrossfitLog(
            day: day,
            patch: [
                "done": isDone,
                "completedOn": isDone ? todayStorageDateKey() : ""
            ]
        )
    }

    func resetCrossfitWeek() {
        webView?.evaluateJavaScript("window.__bfNativeResetCrossfitWeek && window.__bfNativeResetCrossfitWeek();")
    }

    private func evaluateNavigation(on webView: WKWebView, to screen: WorkoutSection) {
        let script = "window.__bfNativeNavigate && window.__bfNativeNavigate('\(screen.rawValue)');"
        webView.evaluateJavaScript(script)
    }

    func applyPendingProgramProgressUpdate() {
        guard let pendingProgramProgress, let webView else { return }
        let script = """
        (window.__bfNativeUpdateProgramProgress ? window.__bfNativeUpdateProgramProgress(\(pendingProgramProgress.phaseID), \(pendingProgramProgress.phaseWeek)) : false);
        """
        webView.evaluateJavaScript(script) { result, _ in
            guard (result as? Bool) == true else { return }
            DispatchQueue.main.async {
                if self.pendingProgramProgress?.phaseID == pendingProgramProgress.phaseID,
                   self.pendingProgramProgress?.phaseWeek == pendingProgramProgress.phaseWeek {
                    self.pendingProgramProgress = nil
                    webView.reload()
                }
            }
        }
    }

    private func applyOptimisticProgramProgress(phaseID: Int, phaseWeek: Int) {
        guard var snapshot else { return }
        guard let phase = snapshot.phases.first(where: { $0.id == phaseID }) ?? snapshot.phases.first else { return }

        let absoluteWeek = ((phase.id - 1) * 9) + phaseWeek
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let startDate = Calendar.current.date(byAdding: .day, value: -((absoluteWeek - 1) * 7), to: startOfToday) ?? startOfToday
        let previousPhaseID = snapshot.settings.currentPhase
        let previousDayIndex = snapshot.settings.currentDayIndex

        snapshot.settings.startDate = storageDateKey(for: startDate)
        snapshot.settings.currentPhase = phase.id
        snapshot.settings.currentDayIndex = previousPhaseID == phase.id && phase.days.indices.contains(previousDayIndex) ? previousDayIndex : 0

        if let data = try? JSONEncoder().encode(snapshot.settings),
           let encoded = String(data: data, encoding: .utf8) {
            WorkoutNativeStorage.save(key: "bf5_s", value: encoded)
        }

        self.snapshot = snapshot
    }

    private func persistSnapshot(_ snapshot: WorkoutEngineSnapshot?) {
        guard let snapshot else { return }
        let cacheURL = cacheURL
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: cacheURL, options: [.atomic])
        }
    }

    private func jsonLiteral(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value) || value is String || value is NSNumber || value is NSNull else {
            return nil
        }

        if let string = value as? String {
            guard let data = try? JSONEncoder().encode(string), let encoded = String(data: data, encoding: .utf8) else {
                return nil
            }
            return encoded
        }

        guard let data = try? JSONSerialization.data(withJSONObject: value, options: []),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return encoded
    }

    private func todayStorageDateKey() -> String {
        storageDateKey(for: Date())
    }

    private func storageDateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct WorkoutBrowser: UIViewRepresentable {
    @ObservedObject var model: WorkoutBrowserModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: nativeStorageSeedScript(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: embeddedModeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: nativeSnapshotBridgeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: nativeStorageBridgeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: "bfNavigation")
        configuration.userContentController.add(context.coordinator, name: "bfStorage")
        configuration.userContentController.add(context.coordinator, name: "bfSnapshot")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleRefreshControl(_:)),
            for: .valueChanged
        )
        webView.scrollView.refreshControl = refreshControl
        model.webView = webView
        webView.load(URLRequest(url: model.homeURL, cachePolicy: .returnCacheDataElseLoad))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        model.webView = webView

        if webView.url == nil && !model.isLoading {
            webView.load(URLRequest(url: model.homeURL, cachePolicy: .returnCacheDataElseLoad))
        } else {
            model.applyPendingNavigationIfNeeded()
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "bfNavigation")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "bfStorage")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "bfSnapshot")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let model: WorkoutBrowserModel

        init(model: WorkoutBrowserModel) {
            self.model = model
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "bfNavigation" {
                guard let screenID = message.body as? String, let screen = WorkoutSection(rawValue: screenID) else { return }

                DispatchQueue.main.async {
                    self.model.syncActiveScreen(screen)
                }
                return
            }

            if message.name == "bfStorage" {
                guard let payload = message.body as? [String: Any], let key = payload["key"] as? String else { return }
                let value = payload["value"] as? String
                WorkoutNativeStorage.save(key: key, value: value)
                return
            }

            if message.name == "bfSnapshot" {
                guard let payload = message.body as? String, let data = payload.data(using: .utf8) else { return }

                do {
                    let snapshot = try JSONDecoder().decode(WorkoutEngineSnapshot.self, from: data)
                    DispatchQueue.main.async {
                        self.model.snapshot = snapshot
                    }
                } catch {
                    return
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
            model.errorMessage = nil
            model.updateNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.isLoading = false
            model.hasLoadedContent = true
            webView.scrollView.refreshControl?.endRefreshing()
            model.updateNavigationState(from: webView)
            model.applyPendingNavigationIfNeeded()
            model.applyNativePresentationMode()
            model.applyPendingProgramProgressUpdate()
            webView.evaluateJavaScript("window.__bfReportScreen && window.__bfReportScreen();")
            model.requestSnapshot()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handle(error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handle(error, webView: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if ["tel", "mailto"].contains(url.scheme?.lowercased()) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        @objc func handleRefreshControl(_ sender: UIRefreshControl) {
            model.reload()
        }

        private func handle(_ error: Error, webView: WKWebView) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }

            model.isLoading = false
            webView.scrollView.refreshControl?.endRefreshing()
            model.errorMessage = "Check your connection, then retry. Your saved workout logs still live in the site once it loads."
            model.updateNavigationState(from: webView)
        }
    }
}

private func nativeStorageSeedScript() -> String {
    let snapshot = WorkoutNativeStorage.snapshot()
    let jsonData = (try? JSONSerialization.data(withJSONObject: snapshot, options: [])) ?? Data("{}".utf8)
    let json = String(data: jsonData, encoding: .utf8) ?? "{}"

    return """
    (function() {
      var seed = \(json);
      try {
        Object.keys(seed).forEach(function(key) {
          if (localStorage.getItem(key) == null && typeof seed[key] === 'string') {
            localStorage.setItem(key, seed[key]);
          }
        });
      } catch (error) {}
    })();
    """
}

private let embeddedModeScript = """
(function() {
  if (window.__bfNativeBridgeLoaded) return;
  window.__bfNativeBridgeLoaded = true;

  function postScreen(screen) {
    try {
      window.webkit.messageHandlers.bfNavigation.postMessage(screen);
    } catch (error) {}
  }

  function currentScreen() {
    var active = document.querySelector('.nav .ntab.on');
    if (!active) return null;
    var label = (active.textContent || '').trim().toLowerCase();
    var map = {
      'home': 'home',
      'workout': 'today',
      'progress': 'history',
      'wod': 'crossfit',
      'program': 'plan'
    };
    return map[label] || null;
  }

  function reportCurrentScreen() {
    var screen = currentScreen();
    if (screen) {
      postScreen(screen);
    }
    return screen;
  }

  function navButtonFor(screen) {
    var labelMap = {
      'home': 'home',
      'today': 'workout',
      'history': 'progress',
      'crossfit': 'wod',
      'plan': 'program'
    };
    var target = labelMap[screen];
    if (!target) return null;

    return Array.from(document.querySelectorAll('.nav .ntab')).find(function(button) {
      return ((button.textContent || '').trim().toLowerCase() === target);
    }) || null;
  }

  window.__bfNativeNavigate = function(screen) {
    var button = navButtonFor(screen);
    if (!button) return false;
    button.click();
    return true;
  };

  window.__bfReportScreen = reportCurrentScreen;

  window.__bfNativeSetLiveMode = function(enabled) {
    if (enabled) {
      document.documentElement.setAttribute('data-bf-live', '1');
    } else {
      document.documentElement.removeAttribute('data-bf-live');
    }
    return true;
  };

  function attachObserver() {
    var nav = document.querySelector('.nav');
    if (!nav) return false;

    reportCurrentScreen();

    var observer = new MutationObserver(function() {
      reportCurrentScreen();
    });

    observer.observe(nav, {
      subtree: true,
      attributes: true,
      attributeFilter: ['class']
    });

    return true;
  }

  (function waitForNav(attempt) {
    if (attachObserver()) return;
    if (attempt > 80) return;
    setTimeout(function() { waitForNav(attempt + 1); }, 150);
  })(0);

  if (!document.getElementById('bf-embedded-style')) {
    var style = document.createElement('style');
    style.id = 'bf-embedded-style';
    style.textContent = `
      html,
      body {
        background: #07111f !important;
      }

      #root {
        max-width: none !important;
        min-height: 100vh !important;
      }

      .screen {
        bottom: 0 !important;
      }

      .nav {
        display: none !important;
      }

      html[data-bf-live="1"],
      html[data-bf-live="1"] body {
        background: #07111f !important;
      }

      html[data-bf-live="1"] .screen {
        padding-top: 8px !important;
      }
    `;
    document.head.appendChild(style);
  }
})();
"""

private let nativeSnapshotBridgeScript = """
(function() {
  if (window.__bfNativeSnapshotBridgeLoaded) return;
  window.__bfNativeSnapshotBridgeLoaded = true;

  function pad2(value) {
    return String(value).padStart(2, '0');
  }

  function todayString() {
    var now = new Date();
    return now.getFullYear() + '-' + pad2(now.getMonth() + 1) + '-' + pad2(now.getDate());
  }

  function storageDateKey(date) {
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
  }

  function readStorage(key, fallback) {
    try {
      var value = localStorage.getItem(key);
      return value ? JSON.parse(value) : fallback;
    } catch (error) {
      return fallback;
    }
  }

  function asDayLogs(day) {
    return Array.isArray(day) ? day : (day ? [day] : []);
  }

  function normalizeLogs(raw) {
    if (!raw || typeof raw !== 'object') return {};
    return Object.entries(raw).reduce(function(result, entry) {
      var date = entry[0];
      var value = entry[1];
      result[date] = asDayLogs(value).filter(Boolean).map(function(item, index) {
        return Object.assign({}, item, {
          completedAt: item.completedAt || (date + 'T00:00:00'),
          sessionId: item.sessionId || (date + '-' + (index + 1))
        });
      });
      return result;
    }, {});
  }

  function currentScreen() {
    var active = document.querySelector('.nav .ntab.on');
    if (!active) return readStorage('bf5_sc', 'home');
    var label = (active.textContent || '').trim().toLowerCase();
    var map = {
      'home': 'home',
      'workout': 'today',
      'progress': 'history',
      'wod': 'crossfit',
      'program': 'plan'
    };
    return map[label] || readStorage('bf5_sc', 'home');
  }

  window.__bfSendSnapshot = function() {
    var payload = {
      screen: currentScreen(),
      settings: readStorage('bf5_s', { startDate: todayString(), currentPhase: 1, currentDayIndex: 0 }),
      logs: normalizeLogs(readStorage('bf5_l', {})),
      phases: (window.WORKOUT_DATA && window.WORKOUT_DATA.phases) || [],
      crossfitWeek: readStorage('bf5_cf_week', null),
      crossfitLogs: readStorage('bf5_cf_logs', {})
    };

    try {
      window.webkit.messageHandlers.bfSnapshot.postMessage(JSON.stringify(payload));
    } catch (error) {}
  };

  window.__bfNativeUpdateCrossfitLog = function(day, patch) {
    try {
      var logs = readStorage('bf5_cf_logs', {});
      logs[day] = Object.assign({}, logs[day] || {}, patch || {});
      localStorage.setItem('bf5_cf_logs', JSON.stringify(logs));
      window.__bfSendSnapshot();
      return true;
    } catch (error) {
      return false;
    }
  };

  window.__bfNativeUpdateProgramProgress = function(phaseID, phaseWeek) {
    try {
      var phases = (window.WORKOUT_DATA && window.WORKOUT_DATA.phases) || [];
      var targetPhaseID = parseInt(phaseID, 10);
      var targetWeek = Math.max(1, Math.min(9, parseInt(phaseWeek, 10) || 1));
      var phase = phases.find(function(item) { return item.id === targetPhaseID; }) || phases[0];
      if (!phase) return false;

      var current = readStorage('bf5_s', { startDate: todayString(), currentPhase: 1, currentDayIndex: 0 });
      var absoluteWeek = ((phase.id - 1) * 9) + targetWeek;
      var startDate = new Date();
      startDate.setHours(0, 0, 0, 0);
      startDate.setDate(startDate.getDate() - ((absoluteWeek - 1) * 7));

      var dayIndex = current.currentPhase === phase.id ? (parseInt(current.currentDayIndex, 10) || 0) : 0;
      if (!phase.days || !phase.days[dayIndex]) {
        dayIndex = 0;
      }

      localStorage.setItem('bf5_s', JSON.stringify(Object.assign({}, current, {
        startDate: storageDateKey(startDate),
        currentPhase: phase.id,
        currentDayIndex: dayIndex
      })));
      window.__bfSendSnapshot();
      return true;
    } catch (error) {
      return false;
    }
  };

  window.__bfNativeResetCrossfitWeek = function() {
    try {
      if (typeof DEFAULT_CROSSFIT_WEEK !== 'undefined') {
        localStorage.setItem('bf5_cf_week', JSON.stringify(DEFAULT_CROSSFIT_WEEK));
      }
      window.__bfSendSnapshot();
      return true;
    } catch (error) {
      return false;
    }
  };

  setTimeout(function() {
    window.__bfSendSnapshot && window.__bfSendSnapshot();
  }, 0);
})();
"""

private let nativeStorageBridgeScript = """
(function() {
  if (window.__bfNativeStorageBridgeLoaded) return;
  window.__bfNativeStorageBridgeLoaded = true;

  var trackedKeys = ['bf5_s', 'bf5_l', 'bf5_sc', 'bf5_cf_week', 'bf5_cf_logs'];

  function shouldTrack(key) {
    return trackedKeys.indexOf(key) !== -1;
  }

  function postValue(key, value) {
    try {
      window.webkit.messageHandlers.bfStorage.postMessage({ key: key, value: value });
    } catch (error) {}
  }

  try {
    trackedKeys.forEach(function(key) {
      var value = localStorage.getItem(key);
      if (value !== null) {
        postValue(key, value);
      }
    });
  } catch (error) {}

  var originalSetItem = Storage.prototype.setItem;
  Storage.prototype.setItem = function(key, value) {
    var result = originalSetItem.apply(this, arguments);
    var trackedKey = String(key);
    if (shouldTrack(trackedKey)) {
      postValue(trackedKey, this.getItem(trackedKey));
      if (window.__bfSendSnapshot) {
        window.__bfSendSnapshot();
      }
    }
    return result;
  };

  var originalRemoveItem = Storage.prototype.removeItem;
  Storage.prototype.removeItem = function(key) {
    var trackedKey = String(key);
    var result = originalRemoveItem.apply(this, arguments);
    if (shouldTrack(trackedKey)) {
      postValue(trackedKey, null);
      if (window.__bfSendSnapshot) {
        window.__bfSendSnapshot();
      }
    }
    return result;
  };
})();
"""

private extension AppSection {
    init(from section: WorkoutSection) {
        switch section {
        case .home:
            self = .home
        case .today:
            self = .today
        case .history:
            self = .history
        case .crossfit:
            self = .crossfit
        case .plan:
            self = .plan
        }
    }
}
