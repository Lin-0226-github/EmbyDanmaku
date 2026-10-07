//
//  AppOrientation.swift
//  EmbyDanmaku
//
//  屏幕方向控制。
//  - 平时保持系统默认行为（跟随手机重力自转）
//  - 播放器点「横屏」时锁定横屏并立即旋到横屏，点「竖屏」旋回竖屏
//  - 退出播放器一律恢复竖屏，不影响其它页面
//
//  iOS 15 没有 requestGeometryUpdate，所以用 UIKit 的标准做法：
//  先在 delegate 里给出当前允许的方向，再用 UIDevice.orientation 触发旋转。
//

import SwiftUI
import UIKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// 当前允许的方向。播放器切换横竖屏时会临时改写它。
    static var orientations: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        Self.orientations
    }
}

// MARK: - 方向控制

enum OrientationController {

    /// 锁定并旋转到横屏（默认往右转一次，左右两种都可以，由系统按当前姿态挑）
    static func landscape() {
        AppDelegate.orientations = .landscape
        rotate(to: .landscapeRight)
    }

    /// 回到竖屏，并解除锁定
    static func portrait() {
        AppDelegate.orientations = .allButUpsideDown
        rotate(to: .portrait)
    }

    private static func rotate(to orientation: UIInterfaceOrientation) {
        if Thread.isMainThread {
            apply(orientation)
        } else {
            DispatchQueue.main.async { apply(orientation) }
        }
    }

    private static func apply(_ orientation: UIInterfaceOrientation) {
        // 1) 告诉系统「我现在要这个方向」
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        // 2) 让窗口立刻按新的方向集合重新布局
        UIViewController.attemptRotationToDeviceOrientation()
        // 3) iOS 15 上偶尔一次不生效，间隔补一次更稳
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        }
    }
}
