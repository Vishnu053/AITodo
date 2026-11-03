import SwiftUI
import AIToDoCore

@main
struct AIToDoApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.didBecomeActive() }
                }
        }
    }
}
