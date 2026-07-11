# Verification Status

Last updated: 2026-07-10

## Automated Evidence

- iOS Simulator: `70` tests passed, `0` failed (iPhone 17, iOS 26.5).
- macOS test target: `33` tests passed, `0` failed.
- SwiftLint strict: `0` violations across `66` Swift files.
- Simulator UI: the Library empty state reports zero real scans and capture availability is explicitly blocked with the mode-specific hardware requirement.
- Simulator UI: persisted capture defaults flow from Settings into a newly started scan; measurement units update the rendered measurement text.
- Simulator UI: Auto-Pilot exposes the Vision-classification choice and accurately blocks live capture on Simulator instead of implying camera support.
- The mode picker maps every UI choice to its matching capture engine, including Auto-Pilot on iPad.
- Local compute validation rejects missing archives and extension-only/corrupt image files, retains models durably, generates a geometry-derived PLY preview, and packages that preview for Mac-to-iPhone return.
- Retained image archives receive bounded exposure and edge-detail analysis; Review shows the measured sample rather than a fabricated coverage map.
- Capture quality provenance is persisted with the scan manifest and embedded in the ZIP handoff, so it survives iOS-to-Mac reconstruction and the returned result package.
- Computed and RoomPlan models derive their displayed triangle count from ModelIO geometry instead of a placeholder label.
- The Mac has an opt-in **Trained splat** path that constructs and runs bounded local COLMAP + Nerfstudio MPS commands, validates the complete binary PLY header/payload and required finite Gaussian properties, clears stale retry artifacts, and preserves trained-versus-geometry-preview provenance. Trainer and installer cancellation terminate isolated descendant process groups; disposable-command tests cover success, subprocess failure, stale outputs, and child-process cancellation.
- Capture archives are recursively validated and ZIP-packaged before Mac handoff. Versioned handoff metadata preserves source scan identity, Auto-Pilot mode, and detail tier; result packages are correlated back to the originating scan and corrupt model payloads are rejected.
- Scan manifests persist scan-relative asset paths and repair legacy container-relative URLs after app relocation. Capture/model replacements and built-in/Blender exports use staged replacement. Mac recompute builds an entire scan revision in a sibling staging directory and atomically swaps it only after the model, preview, and manifest are ready.
- Network resources use UUID-scoped Application Support inboxes, retain independent progress observations for overlapping transfers, serialize Mac compute jobs, and remove inbox/result ZIP artifacts after import or transfer completion.
- Measurement persistence, metric-distance calculation, CSV output, splat PLY generation, and result-package PLY round trips are covered by unit tests.
- The real ObjectCapture, RoomPlan, and Landscape surfaces now share a live HUD backed only by engine state, AR tracking, and saved-frame counts. The former painted-camera `ViewfinderScreen` prototype has been removed.
- On-device compute consistently declares and persists `Reduced` output; Mac handoff preserves the requested detail tier. This policy and its UI-facing labels are covered by unit tests.
- Export is verified for USDZ pass-through and ModelIO USD, OBJ (including its material sidecar), STL, and PLY output. macOS also provides GLB and embedded-texture FBX through a locally installed Blender runtime; declared GLB length/chunks and FBX version/footer are validated, failed conversions preserve prior exports, and a local integration test converts a real USDA fixture to both formats.
- The macOS external-tools settings panel reports Blender and trained-splat readiness. It can bootstrap COLMAP plus a pinned Nerfstudio `1.1.5` environment and refreshes runtime discovery without an app restart; its subprocess sequence is covered by a disposable-command integration test.

## Remaining Product Work

- The briefing screen is intentionally guidance-only. Live lighting, thermal, and object-analysis diagnostics are not implemented and should only be added when backed by device APIs with clear confidence and failure states.
- Capture, reconstruction, handoff, and scale-sensitive measurement behavior still need the physical-device UAT below before a production release.

## Physical-Device UAT Required

No iPhone or iPad is currently attached to this Mac. The following cannot be proven in Simulator:

1. ObjectCaptureSession reaches its documented `.completed` terminal state and the resulting directory contains every expected image frame.
2. Landscape ARKit captures valid, non-empty JPEG frames and drains them before persistence.
3. Auto-Pilot receives a live camera frame, settles on an appropriate Vision mode, and transitions into the selected capture engine.
4. RoomPlan on LiDAR hardware exports a USDZ that reaches Viewer and Export.
5. RealityKit photogrammetry completes at each supported detail request on the target Mac and device.
6. A real Multipeer handoff transfers the ZIP capture, model, and geometry-preview PLY in both directions.
7. SceneKit model-surface hit testing produces sensible real-world measurement distances for the model scale.
8. The direct-distribution Mac app can run the installed COLMAP + Nerfstudio runtime on a representative image capture, produce a renderable trained PLY, and return that PLY through an actual Multipeer result package.
9. A reconstructed, textured capture USDZ converts through the macOS Blender path into GLB and FBX that open in a third-party viewer.

## Known Constraints

- Geometry-derived PLY previews are vertex-based splat previews, not trained neural radiance fields.
- This Mac has COLMAP 4.1.0 plus a project-external Nerfstudio 1.1.5 environment with MPS available and `pymeshlab` installed for export. The direct-distribution Mac target is intentionally unsandboxed because macOS rejects launching this writable local runtime from a sandboxed app. Installer command construction and disposable end-to-end service tests are verified; a real capture-to-trained-PLY run remains unproven.
- iOS local RealityKit compute currently records Reduced detail because that is the SDK detail request exposed on this target.
- GLB and FBX are macOS-only Blender conversions; iOS offers USDZ pass-through plus ModelIO USD, OBJ, STL, and PLY output.
- Live coverage, lighting, thermal, object dimensions, and scene-completeness diagnostics remain intentionally absent until backed by concrete device measurements and confidence states.
- The historical design/audit documents describe the original prototype. They are not a source of current behavior; consult the source and this verification record.
