# 3DSeen Production Contract

Last updated: 2026-07-21

This document is the canonical repository-level definition of production behavior. Source code and automated tests are the implementation authority; `docs/VERIFICATION-STATUS.md` records evidence and external gates. Files under `docs/design-spec/`, `docs/design-ref/`, `docs/review/`, and `docs/audit/`, plus `docs/EXECUTION-PLAN.md`, are historical design and review inputs. They may explain intent but do not override this contract.

## Supported products

- iPhone and iPad run the same persisted Studio workflow with adaptive layouts: Library → Mode → Briefing → Detail → Capture → Review → Compute → Viewer → Export.
- macOS provides Library, Viewer, Compute, Export, and Settings panes and acts as an optional local reconstruction worker.
- Minimum deployment targets are iOS/iPadOS 17 and macOS 14. Local verification supports Xcode 26.3 or newer; hosted CI deliberately selects exact Xcode 26.3 for reproducibility.

## Capture

- Object capture uses one custom ARKit session plus Vision foreground-instance detection. Guidance points must be real LiDAR depth samples or ARKit tracked feature points projected into the selected subject mask; synthetic coverage is prohibited.
- Object photos are admitted only from current normal tracking plus measured subject-lock freshness, luminance/edge contrast, motion, interval, translation novelty, and bounded writer backlog. Manual capture remains available.
- Finish closes frame admission and waits for every accepted JPEG write before exposing the capture archive. Capture attempts are UUID-scoped so stale Vision, Auto-Pilot, writer, or SDK callbacks cannot complete a newer attempt.
- Space capture uses RoomPlan and requires supported LiDAR hardware.
- Landscape capture uses ARKit world tracking and retained image frames.
- Auto-Pilot uses Vision classification to recommend a real capture engine; it is not a separate reconstruction algorithm.
- Simulator and unsupported-hardware paths must block honestly. No synthetic capture may be presented as a real scan.
- Review metrics may only display retained-frame measurements or explicit unavailable states. Geometry coverage, dimensions, lighting, or thermal claims must be tied to measured APIs.

## Compute and handoff

- On-device image reconstruction uses RealityKit photogrammetry and is labeled Reduced where that is the actual request.
- RoomPlan USDZ may proceed directly as a computed model.
- Mac reconstruction uses RealityKit photogrammetry. Optional trained-splat output requires a validated local COLMAP and pinned Nerfstudio runtime.
- Scan assets and `ScanAssetManifest` are authoritative durable scan data. Cross-launch handoff jobs use separate atomic phone and Mac journals; the transient processing state machine is not durable job authority. Completed Mac results can be rebuilt from the retained manifest and resent after authenticated status reconciliation.
- Returned results must correlate by authenticated peer, job, scan, byte count, and SHA-256 before transactionally replacing durable assets. Resource-before-control ordering is bounded until the typed descriptor arrives; unsolicited resources are rejected.
- Handoff is not production-secure until explicit peer choice, user-approved authenticated pairing, typed job controls, cancellation, timeout, retry, and relaunch reconciliation are all implemented and physically validated. Transport encryption alone is insufficient.

## Library, viewer, and export

- Library actions are derived from persisted capture/compute state and must never route a missing model to Viewer or Export.
- Persisted models, measurements, and Library thumbnails survive relaunch and sandbox relocation through scan-relative manifests. Photo captures derive a bounded thumbnail from a validated real frame outside the raw archive; no-photo modes use a semantic mode/status fallback rather than fabricated geometry.
- Geometry previews are labeled separately from trained Gaussian splats.
- iOS/iPadOS support USDZ pass-through and ModelIO USD, OBJ, STL, and PLY export. macOS additionally supports GLB and FBX through an installed Blender runtime.
- Export replacement is staged and transactional. Formats unavailable on a platform must not be advertised there.

## Persistence and integrity

- `ScanSession` and `ScanAssetStore` remain the scan authority.
- Capture, thumbnail, model, preview, manifest, and export updates must be staged and validated before replacement.
- Rename, deletion, retention, and orphan cleanup must update durable metadata and files consistently.
- Legacy manifests and v1 handoff packages remain readable during migration.

## Privacy, distribution, and quality gates

- Camera, local-network, stored-file, and optional external-tool behavior must be represented in privacy metadata and user-facing descriptions.
- A release candidate requires strict SwiftLint, all iOS/macOS unit and UI tests, XcodeGen drift validation, unsigned Release builds, workflow validation, and `git diff --check`.
- Signed iOS distribution, Developer ID signing/notarization, physical capture, real Multipeer transfer, representative trained-splat execution, and third-party GLB/FBX validation remain external credential/hardware/runtime gates. They must be recorded as blocked until actually executed.

## Change policy

A behavior change must update this contract, relevant tests, and `docs/VERIFICATION-STATUS.md` in the same release work. Historical design documents should not be silently rewritten to imply they describe current production behavior.
