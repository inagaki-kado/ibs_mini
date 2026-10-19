import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Diagnostics.shared.start() // 「止まった」原因をあとから調べられるよう、端末内に記録を残す
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // HDMI 等の外部ディスプレイには専用のシーン（ExternalSceneDelegate）を使う。
        // これを宣言しないと iOS 標準のミラーリングになり、黒帯が出て、ズームなどのアプリ側の変形も一致しない
        let isExternal = connectingSceneSession.role == .windowExternalDisplayNonInteractive
        let config = UISceneConfiguration(name: isExternal ? "External Display" : "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = isExternal ? ExternalSceneDelegate.self : SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = HUDViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 大会中に画面がスリープしないようにする
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func sceneWillResignActive(_ scene: UIScene) {
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
