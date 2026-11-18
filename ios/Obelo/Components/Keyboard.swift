import SwiftUI
import UIKit

// Closing the keyboard, everywhere:
//  - tapping anywhere outside a text field (a window-level recogniser that never swallows the
//    tap, so buttons and rows still work, and ignores taps on text fields themselves)
//  - a "Done" button above the keyboard (keyboardDoneButton), the only way out of multi-line
//    fields, where Return adds a new line
//  - scrolling (Page uses .scrollDismissesKeyboard(.immediately))

enum Keyboard {
    static func dismiss() {
        #if SHARE_EXTENSION
        // UIApplication.shared isn't available in extensions; the share sheet's own window does it
        ShareKeyboard.dismiss?()
        #else
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    #if !SHARE_EXTENSION
    private final class TapOutside: NSObject, UIGestureRecognizerDelegate {
        @objc func tapped() { Keyboard.dismiss() }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let v = view {
                if v is UITextField || v is UITextView { return false }
                view = v.superview
            }
            return true
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    private static let handler = TapOutside()

    /// Call once the window exists; safe to call repeatedly
    static func installTapToDismiss() {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows where !(window.gestureRecognizers ?? []).contains(where: { $0.name == "vt.dismissKeyboard" }) {
            let tap = UITapGestureRecognizer(target: handler, action: #selector(TapOutside.tapped))
            tap.name = "vt.dismissKeyboard"
            tap.cancelsTouchesInView = false
            tap.delegate = handler
            window.addGestureRecognizer(tap)
        }
    }
    #endif
}

#if SHARE_EXTENSION
enum ShareKeyboard {
    static var dismiss: (() -> Void)?
}
#endif

extension View {
    /// Adds a "Done" button above the keyboard. Attach once per navigation stack / sheet root.
    @ViewBuilder func keyboardDoneButton() -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { Keyboard.dismiss() }.fontWeight(.semibold)
            }
        }
        #else
        self
        #endif
    }
}
