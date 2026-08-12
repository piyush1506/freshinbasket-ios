import Flutter
import UIKit
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil {
        let options = FirebaseOptions(googleAppID: "1:547366347776:ios:bd0c79190db5df9db1a4e5",
                                      gcmSenderID: "547366347776")
        options.apiKey = "AIzaSyCIsHWeUaNmqmDmnr3yd6yGH-pWs2S1a5M"
        options.projectID = "freshinbasketapp"
        options.storageBucket = "freshinbasketapp.firebasestorage.app"
        options.bundleID = "in.freshinbasket.app"
        FirebaseApp.configure(options: options)
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

