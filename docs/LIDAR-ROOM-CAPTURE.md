# Textured room and space capture

Choose **Rooms & Spaces**, read the room checklist, and start capture on a LiDAR-equipped iPhone or iPad with ARKit mesh and scene-depth support. Walk slowly around a section, viewing walls, floors, furniture, and irregular surfaces from several angles. Keep the room still and evenly lit. The HUD reports retained camera frames, actual surface faces, tracking state, sampled-preview texture coverage, and available face categories. On supported devices, ARKit can label faces as wall, floor, ceiling, table, seat, window, or door.

Tap **Save texture** while pointing the center of the camera at a material to save a reusable square PNG snapshot. These photographs include the lighting present during capture. They are not seamless textures or measured albedo, roughness, metallic, or normal maps.

Finish pauses capture and projects camera images onto the captured triangles, using depth confidence and depth agreement to reject unrelated surfaces. The exporter embeds the images in USDZ and groups faces by texture view and available category. Faces without an acceptable view remain neutral gray rather than borrowing unrelated colors. No boxes or synthetic surfaces replace the captured mesh. Review reports texture coverage over the completed mesh and the detected face categories. Categories are approximate labels on triangles; they do not create unique, editable object identities.

Inspect the model in Viewer using Original Texture, then share USDZ from Export. The optional captured surface texture section shares PNG snapshots separately. Deleting source capture frames leaves the model and saved snapshots intact.

To view a completed room on Mac, transfer the USDZ through Files or AirDrop and choose **Import room model** in the Mac library. The import preserves embedded geometry and textures, retains its own copy, and leaves the selected source file intact. Separate snapshots can be transferred as PNG files. For OBJ/OpenUSD exports with companion material or image files, Share package sends a ZIP containing the model and its dependencies; unzip it together before opening the model.

Capture is bounded to 256 texture camera keyframes and 500,000 mesh triangles to limit memory and export cost. Large spaces should be captured in sections. These limits do not guarantee complete coverage or a particular performance level; check the result before discarding source data.

This is an ARKit LiDAR surface scanner, not a survey-grade metrology instrument. Its mesh approximates visible, tracked surfaces at the phone's sensor resolution; it does not reconstruct hidden surfaces or guarantee dimensional accuracy. Glass, mirrors, moving objects, deep occlusions, and fine details can create gaps or poor texture matches.

## Physical validation still required

Scan a room containing an irregular wall or surface, furniture, patterned materials, and an occluding object. Verify geometry is measured rather than box-fitted, textures stay aligned, occluded surfaces are not painted from foreground objects, snapshots match the targeted material, and USDZ displays correctly on iPhone, iPad, and Mac. Check cancellation, interruptions, repeated scans, heat, and storage under a sustained walkthrough. Automated fixture tests and simulators cannot establish these hardware outcomes.
