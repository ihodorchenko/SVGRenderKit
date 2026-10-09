import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = UIColor.white

        let navigationController = UINavigationController()
        navigationController.viewControllers = [ViewController2()]
        window.rootViewController = navigationController

        self.window = window
        window.makeKeyAndVisible()
    }

}
