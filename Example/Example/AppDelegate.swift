import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // `Scripts/webkit-parity.sh` drives the browser oracle: with `-webkitParity <corpus-dir>`
        // the app renders the corpus in a web view, writes the rasters and exits instead of
        // showing the gallery (B122). The work is asynchronous so launch is not blocked.
        if WebKitParityRunner.runIfRequested() { return true }
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }

}
