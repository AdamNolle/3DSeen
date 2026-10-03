# 3DSeen Production Contract

Last updated: 2026-10-02

This document is the canonical repository-level definition of production behavior. Source code and automated tests are the implementation authority; `docs/VERIFICATION-STATUS.md` records evidence and external gates. Files under `docs/design-spec/`, `docs/design-ref/`, `docs/review/`, and `docs/audit/`, plus `docs/EXECUTION-PLAN.md`, are historical design and review inputs. They may explain intent but do not override this contract.

## Supported products

- Empty phone and iPad libraries keep **New Scan** prominent and hide search and mode-filter controls until saved scans exist; iPad category navigation remains available. Removing the last scan clears stale search and mode filters so newly created scans remain visible.
- iPhone and iPad run the same persisted Studio workflow with adaptive layouts: Library → Mode → Briefing → Detail → Capture → Review → Compute → Viewer → Export.
- macOS provides Library, Viewer, Compute, Export, and Settings panes and acts as an optional local reconstruction worker.
- macOS uses a single Studio window with persistent navigation. Library grids adapt to available width; phone and iPad controls respect larger touch areas, Reduce Motion, and Reduce Transparency.
- Minimum deployment targets are iOS/iPadOS 17 and macOS 14. Local verification currently uses Xcode 27.0.1; hosted CI selects exact Xcode 26.6 for reproducibility.

## Capture

- Object capture uses one custom ARKit session plus Vision foreground-instance detection. Guidance points must be real LiDAR depth samples or ARKit tracked feature points projected into the selected subject mask; synthetic coverage is prohibited.
- Object photos are admitted only from current normal tracking plus measured subject-lock freshness, luminance/edge contrast, motion, interval, translation novelty, and bounded writer backlog. Manual capture remains available.
- Finish closes frame admission and waits for every accepted JPEG write before exposing the capture archive. Capture attempts are UUID-scoped so stale Vision, Auto-Pilot, writer, or SDK callbacks cannot complete a newer attempt.
- Space capture requires ARKit scene-reconstruction mesh and scene-depth support on LiDAR hardware. When supported, it requests classified mesh faces and retains ARKit's approximate wall, floor, ceiling, table, seat, window, or door category; otherwise it falls back to unclassified mesh capture. It retains actual world-space triangles and depth-checked RGB camera projections; plane detection is disabled to avoid flattening irregular surfaces. USDZ groups faces by texture view and available face category. Unobserved faces remain neutral, and face counts and texture coverage describe the measured mesh rather than complete room coverage.
- Face categories label individual triangles; they do not segment every physical object into a unique, editable object. The live texture percentage describes only the bounded preview sample, while the completed scan report computes coverage over the exported mesh. Geometry is an ARKit LiDAR approximation of visible, tracked surfaces, not a metrology guarantee or a reconstruction of hidden surfaces.
- Surface snapshots are user-requested center crops saved as PNG. They retain captured lighting; they are not seamless textures or measured PBR maps. Embedded model textures and reusable snapshots survive deletion of source frames.
- Landscape capture uses ARKit world tracking and retained image frames.
- Guided object capture projects LiDAR depth samples through the camera intrinsics into ARKit world coordinates and renders a bounded, persistent dot cloud on the detected object. Where ARKit mesh reconstruction is available, RealityKit mesh occlusion keeps accumulated dots behind nearer tracked surfaces. The HUD shows the number of unique spatial samples; light haptic feedback fires at new-surface milestones. Devices without LiDAR keep the screen-space feature-point fallback and do not claim depth coverage. Dots are live scan guidance, while image capture and object reconstruction remain separate stages; the dot cloud is not a final textured mesh or a metrology result.
- Auto-Pilot uses Vision classification to recommend a real capture engine; it is not a separate reconstruction algorithm.
- Simulator and unsupported-hardware paths must block honestly. No synthetic capture may be presented as a real scan.
- Review metrics may only display retained-frame measurements or explicit unavailable states. Geometry coverage, dimensions, lighting, or thermal claims must be tied to measured APIs.

## Compute and handoff

- On-device image reconstruction uses RealityKit photogrammetry and is labeled Reduced where that is the actual request.
- Completed textured LiDAR USDZ proceeds directly to Viewer and Export. Mac room-model import preserves embedded USDZ geometry and textures without photogrammetry.
- Mac reconstruction uses RealityKit photogrammetry. Optional trained-splat output requires a validated local COLMAP and pinned Nerfstudio runtime.
- Handoff protocol v3 pairs with ephemeral Curve25519 key agreement and derives the comparison code and stored credential from that shared secret. A separate v3 Keychain namespace invalidates old trust records, and protocol versions below 3 are rejected; both devices must update and pair again. After pairing, control messages use authenticated ChaChaPoly frames and scan/result files are encrypted in authenticated bounded chunks before Multipeer transfer. This protects handoff contents when transport encryption terminates at an intermediary.
- Scan assets and `ScanAssetManifest` are authoritative durable scan data. Cross-launch handoff jobs use separate atomic phone and Mac journals; the transient processing state machine is not durable job authority. Completed Mac results can be rebuilt from the retained manifest and resent after authenticated status reconciliation.
- Returned results must correlate by authenticated peer, job, scan, byte count, and SHA-256 before transactionally replacing durable assets. Resource-before-control ordering is bounded until the typed descriptor arrives; unsolicited resources are rejected.
- Handoff is not production-secure until explicit peer choice, user-approved authenticated pairing, typed job controls, cancellation, timeout, retry, and relaunch reconciliation are all implemented and physically validated. Transport encryption alone is insufficient.

## Library, viewer, and export

- Library actions are derived from persisted capture/compute state and must never route a missing model to Viewer or Export.
- Persisted models, measurements, and Library thumbnails survive relaunch and sandbox relocation through scan-relative manifests. Photo captures derive a bounded thumbnail from a validated real frame outside the raw archive; no-photo modes use a semantic mode/status fallback rather than fabricated geometry.
- Geometry previews are labeled separately from trained Gaussian splats.
- iOS/iPadOS support USDZ pass-through and ModelIO USD, OBJ, STL, and PLY export. macOS additionally supports GLB and FBX through an installed Blender runtime.
- Export replacement is staged and transactional. Native conversions load texture resources before writing. App-managed exports isolate each format in its own directory; iOS/iPadOS sharing packages models with companion materials/images into ZIP so relative references survive transfer. Self-contained exports retain direct sharing. Formats unavailable on a platform must not be advertised there.
- Measurements are saved to both the database and portable manifest with rollback on failure. Scan display names must never become unvalidated filesystem paths.

## Persistence and integrity

- `ScanSession` and `ScanAssetStore` remain the scan authority.
- Capture, thumbnail, model, preview, manifest, and export updates must be staged and validated before replacement.
- Rename, deletion, retention, and orphan cleanup must update durable metadata and files consistently.
- Legacy manifests and v1 handoff packages remain readable during migration.

## Privacy, distribution, and quality gates

- Camera, local-network, stored-file, and optional external-tool behavior must be represented in privacy metadata and user-facing descriptions.
- A release candidate requires strict SwiftLint, all iOS/macOS unit and UI tests, XcodeGen drift validation, unsigned Release builds, workflow validation, and `git diff --check`.
- Signed iOS distribution, Developer ID signing/notarization, physical capture, real Multipeer transfer, representative trained-splat execution, and third-party GLB/FBX validation remain external credential/hardware/runtime gates. They must be recorded as blocked until actually executed.

## Bounded real-time LiDAR coverage
Room scans retain accepted mesh geometry up to the 500,000-triangle export budget and guide users to save a section when the mesh, 256-frame, or dot-coverage budget is reached. Per-anchor mesh and face-category totals are incrementally maintained for capture feedback. Over-budget anchor updates are skipped without deleting valid partial geometry. Object segmentation and world-space object dots continue to update from live camera frames after stored texture-frame capture reaches its limit; haptic feedback remains rate-limited to discovery and coverage milestones.

## Change policy

A behavior change must update this contract, relevant tests, and `docs/VERIFICATION-STATUS.md` in the same release work. Historical design documents should not be silently rewritten to imply they describe current production behavior.
