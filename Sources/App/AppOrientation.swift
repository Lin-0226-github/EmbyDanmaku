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
import ObjectiveC

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

    /// 旋转后系统更新窗口安全区需要一点时间，分两次广播通知让界面重读
    static func scheduleSafeAreaRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: .refreshSafeArea, object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            NotificationCenter.default.post(name: .refreshSafeArea, object: nil)
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

extension Notification.Name {
    /// 旋转后重读窗口安全区
    static let refreshSafeArea = Notification.Name("LplayersRefreshSafeArea")
}

// MARK: - 底部手势让位（防误触退出）
//
// iOS 15 没有 SwiftUI 的 defersSystemGestures（那是 iOS 16 的 API），
// UIKit 的 preferredScreenEdgesDeferringSystemGestures 又是只读、只能子类重写；
// SwiftUI 的播放器界面是 UIHostingController，无法改子类。
// 所以用 ObjC runtime 给「最上层全屏 VC 的动态类」替换该 getter：
//   · 实例上挂了关联对象 → 返回它（播放器：横屏 .bottom，退出恢复 []）
//   · 没挂 → 调原实现（其它页面 / 其它 VC 行为完全不变）

private var kDeferEdgesKey: UInt8 = 0

enum ScreenEdgeGestures {

    private typealias OriginFn = @convention(c) (NSObject, Selector) -> UIRectEdge
    private static var patchedClasses: [String] = []

    /// 开 / 关「底部上滑需两次才退出主屏」。只影响调用时最上层的全屏 VC（即播放器）。
    static func deferBottomGestures(_ deferIt: Bool) {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            else { return }

            // 沿 presented 链走到最上层（播放器是 fullScreenCover 展示的）
            var vc = root.presentedViewController ?? root
            while let next = vc.presentedViewController { vc = next }

            patchIfNeeded(type(of: vc))

            let edges: UIRectEdge = deferIt ? .bottom : []
            objc_setAssociatedObject(vc, &kDeferEdgesKey,
                                     NSValue(uiRectEdge: edges), .OBJC_ASSOCIATION_RETAIN)
            vc.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        }
    }

    /// 对指定类只打一次补丁：把 preferredScreenEdgesDeferringSystemGestures 的实现
    /// 换成「先读关联对象，没有就走原实现」。因为未挂关联对象的实例走原逻辑，
    /// 即使 Method 对象来自公共基类，也不会影响其它视图控制器。
    private static func patchIfNeeded(_ cls: AnyClass) {
        let name = String(describing: cls)
        guard !patchedClasses.contains(name) else { return }
        patchedClasses.append(name)

        let sel = #selector(getter: UIViewController.preferredScreenEdgesDeferringSystemGestures)
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        let origin = unsafeBitCast(method_getImplementation(method), to: OriginFn.self)
        let block: @convention(block) (NSObject, Selector) -> UIRectEdge = { holder, _ in
            if let v = objc_getAssociatedObject(holder, &kDeferEdgesKey) as? NSValue {
                return v.uiRectEdgeValue
            }
            return origin(holder, sel)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}

// MARK: - 安全区

/// 读取「真实」的窗口安全区。
/// 播放器为了铺满整屏，GeometryReader 上加了 .ignoresSafeArea()，
/// 此时 SwiftUI 的 safeAreaInsets 会变成 0，顶栏会被刘海 / 圆角切掉，
/// 所以这里直接从 UIWindow 拿原始值，自己给控制层补 padding。
enum ScreenSafeArea {

    static var insets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window.safeAreaInsets
            }
        }
        for scene in scenes {
            if let window = scene.windows.first, window.bounds.width > 0 {
                return window.safeAreaInsets
            }
        }
        return .zero
    }
}
