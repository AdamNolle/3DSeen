# Textured room and space capture

Choose **Rooms & Spaces**, read the room checklist, and start capture on a LiDAR-equipped iPhone or iPad with ARKit mesh and scene-depth support. Walk slowly around a section, viewing walls, floors, furniture, and irregular surfaces from several angles. Keep the room still and evenly lit. The HUD reports retained camera frames, actual surface faces, and tracking state.

Tap **Save texture** while pointing the center of the camera at a material to save a reusable square PNG snapshot. These photographs include the lighting present during capture. They are not seamless textures or measured albedo, roughness, metallic, or normal maps.

Finish pauses capture and projects camera images onto the captured triangles, using depth confidence and depth agreement to reject unrelated surfaces. The exporter embeds the images in USDZ. Faces without an acceptable view remain neutral gray rather than borrowing unrelated colors. No boxes or synthetic surfaces replace the captured mesh. Glass, mirrors, moving objects, unseen areas, and fine details beyond LiDAR resolution may produce gaps or poor results.

Review shows the actual triangle and textured-triangle counts. Inspect the model in Viewer using Original Texture, then share USDZ from Export. The optional captured surface texture section shares PNG snapshots separately. Deleting source capture frames leaves the model and saved snapshots intact.

To view a completed room on Mac, transfer the USDZ through Files or AirDrop and choose **Import room model** in the Mac library. The import preserves embedded geometry and textures, retains its own copy, and leaves the selected source file intact. Separate snapshots can be transferred as PNG files.

Capture is bounded to 256 texture camera keyframes and 500,000 mesh triangles to limit memory and export cost. Large spaces should be captured in sections. These limits do not guarantee complete coverage or a particular performance level; check the result before discarding source data.

## Physical validation still required

Scan a room containing an irregular wall or surface, furniture, patterned materials, and an occluding object. Verify geometry is measured rather than box-fitted, textures stay aligned, occluded surfaces are not painted from foreground objects, snapshots match the targeted material, and USDZ displays correctly on iPhone, iPad, and Mac. Check cancellation, interruptions, repeated scans, heat, and storage under a sustained walkthrough. Automated fixture tests and simulators cannot establish these hardware outcomes.
