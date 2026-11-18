import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
#endif

// One name for the system image and colour types, so shared code doesn't need `#if os(…)`.
// The rest of the iPhone/Mac differences are in Obelo/Core/Platform.swift.
