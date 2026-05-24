//
//  UnityViewStack.swift
//  flutter_embed_unity_ios
//
//  Created by James Allen on 28/08/2023.
//

import Foundation


// This class is responsible for making sure that Unity is only ever attached to the
// topmost view in the stack. Unity cannot be attached to more than one view, so there
// should only ever be one EmbedUnity widget on a Flutter screen - however we still
// need to account for the fact that when pushing a new Flutter route / screen onto
// the Navigator stack, both screens are still alive and so we can end up with more
// than one PlatformView at the same time (but only the top one will be visible)
// See https://developer.apple.com/documentation/uikit/uiviewcontroller
// See https://developer.apple.com/documentation/uikit/uiview
// See https://developer.apple.com/documentation/swift/using-key-value-observing-in-swift
class UnityViewStack: NSObject {
    
    // This could possibly be implemented as a Queue / Stack collection, but it may
    // be possible that a view which isn't the topmost one gets disposed (eg during
    // a Navigator.of(contect).pushAndRemoveUntil ?) so safest just to use a list
    private var viewStack = [UnityViewController]()
    
    func pushView(_ viewController: UnityViewController) {
        // Unity can only be attached to one view at a time. Therefore, check
        // if there are any other active views, and detatch Unity from them first
        viewStack.forEach { existingViewController in
            existingViewController.detachUnity()
        }
        
        // attach Unity to the new view
        let unityPlayerSingleton = UnityPlayerSingleton.getInstance()
        viewController.attachUnity(unityPlayerSingleton)
        
        // Add view to the stack
        viewStack.append(viewController)
        NSLog("UnityViewStack: pushed Unity view \(viewController.viewId) onto stack")
        
        // Dart `unmountUnity` is the authoritative detach signal. UIKit
        // disappear can also be caused by a modal, keyboard, navigation overlay,
        // or another route covering this view, so it must not drive cleanup.
        viewController.viewDidDisappear = { viewId in
            NSLog("UnityViewStack: Unity view \(viewId) disappeared; diagnostic only, waiting for Dart unmountUnity")
        }
        
        // However it may reappear if it wasn't destroyed (eg it was obscured underneath
        // another screen, and now has reappeared), in which case push it back onto the stack
        viewController.viewDidAppear = { viewId in
            LifecycleEventEmitter.firstFrameSeen(viewId: viewId)
            LifecycleEventEmitter.foregroundActive(true, viewId: viewId)
            if !self.viewStack.contains(where: {$0.viewId == viewId}) {
                NSLog("UnityViewStack: View \(viewId) has reappeared, pushing back onto stack")
                self.pushView(viewController)
            }
        }
        // Resume unity
        unityPlayerSingleton.pause(false)
        LifecycleEventEmitter.foregroundActive(true, viewId: viewController.viewId)
    }

    func popCurrentView() {
        guard let currentViewController = viewStack.last else {
            NSLog("UnityViewStack: unmountUnity requested with no Unity view in stack")
            return
        }

        popView(currentViewController)
    }

    private func popView(_ viewController: UnityViewController) {
        // Detatch Unity from the view
        viewController.detachUnity()
        // Remove from the stack
        viewStack = viewStack.filter { $0 != viewController }
        NSLog("Detached Unity from popped view")

        let unityPlayerSingleton = UnityPlayerSingleton.getInstance()
        
        if(!viewStack.isEmpty) {
            // If there are any remaining views in the stack, attach Unity to the last view to be
            // added to the stack
            viewStack.last?.attachUnity(unityPlayerSingleton)
            NSLog("Reattached Unity to existing view")
            // I don't know why, but when Unity is reattached to an existing view
            // we need to pause AND resume (even though Unity was never paused?):
            unityPlayerSingleton.pause(true)
            unityPlayerSingleton.pause(false)
        }
        else {
            // No more Unity views, so pause
            NSLog("No more EmbedUnity widgets in stack, pausing Unity")
            unityPlayerSingleton.pause(true)
            LifecycleEventEmitter.foregroundActive(false, viewId: viewController.viewId)
        }
    }
}
