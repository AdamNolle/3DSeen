# 3DSeen

**3DSeen** is a professional-grade, multi-modal 3D scanning ecosystem for iOS and macOS. It maximizes physical hardware limits for photogrammetry and LiDAR to achieve the highest possible dimensional accuracy and texture fidelity.

## Architecture

The project employs a flexible, dual-option compute pipeline and a Hub and Spoke capture architecture, driven by a thread-safe MVVM-C State Machine (`ProcessingStateMachine`).

### Capture Engine (iOS)
- **Object Capture:** Uses iOS 17's `ObjectCaptureSession` and `ObjectCaptureView` for high-fidelity photogrammetry with interactive AR bounding boxes.
- **Space Capture:** Utilizes Apple's `RoomPlan` API to generate parametric 3D structural blocks of rooms and furniture.
- **Landscape Capture:** Leverages ARKit Visual Inertial Odometry (VIO) for outdoor environments where LiDAR is blinded by the sun.
- **Auto-Pilot Mode:** A CoreML vision model analyzes the live camera feed to auto-suggest the optimal capture mode.

### Compute Pipeline
- **On-Device Compute (iOS):** Uses RealityKit natively on the iPhone. It actively monitors `ProcessInfo.thermalState` to prevent hardware throttling, pausing the queue automatically if necessary.
- **Desktop Offload (macOS Companion):** Uses `MultipeerConnectivity` for seamless local network handoff. Raw scan ZIPs are sent to a Mac to leverage native Apple Silicon accelerators (M-Series GPU and Neural Engine) for maximum rendering speed without thermal constraints.

## Requirements
- **iOS App:** iOS 17.0+ (Requires iPhone with LiDAR for optimal Space/Object capture).
- **macOS App:** macOS 14.0+ (Apple Silicon recommended for offloaded photogrammetry).
- **Xcode:** 15.0+

## Setup & Build Instructions

This project uses `XcodeGen` to manage the `.xcodeproj` file. This prevents merge conflicts and keeps the repository clean.

1. Install XcodeGen (if not already installed):
   ```bash
   brew install xcodegen
   ```
2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
3. Open `3DSeen.xcodeproj` in Xcode and select either the **3DSeen-iOS** or **3DSeen-macOS** target to build and run.
