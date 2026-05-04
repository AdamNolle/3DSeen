import SwiftUI
import RealityKit

/// Allows the user to instantly preview the generated 3D model in AR and drop measurement pins.
struct InstantARPreviewView: View {
    let modelURL: URL
    
    @State private var isPlacingPin = false
    
    var body: some View {
        ZStack {
            // Native ARView for rendering the USDZ
            ARViewContainer(modelURL: modelURL, isPlacingPin: $isPlacingPin)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        isPlacingPin.toggle()
                    }) {
                        Image(systemName: isPlacingPin ? "mappin.circle.fill" : "mappin.circle")
                            .font(.largeTitle)
                            .foregroundColor(isPlacingPin ? .red : .blue)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
                
                if isPlacingPin {
                    Text("Tap on the model to place a measurement pin")
                        .font(.headline)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .padding(.bottom, 30)
                }
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let modelURL: URL
    @Binding var isPlacingPin: Bool
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Load the USDZ model
        do {
            let entity = try Entity.load(contentsOf: modelURL)
            let anchor = AnchorEntity(plane: .horizontal)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        } catch {
            print("Failed to load AR model: \(error)")
        }
        
        // Setup tap gesture for pins
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.isPlacingPin = isPlacingPin
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: ARViewContainer
        var isPlacingPin: Bool = false
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard isPlacingPin, let arView = recognizer.view as? ARView else { return }
            
            let location = recognizer.location(in: arView)
            
            // Perform raycast
            if let result = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
                // Place a visual pin
                let pinMesh = MeshResource.generateSphere(radius: 0.01)
                let material = SimpleMaterial(color: .red, isMetallic: false)
                let pinEntity = ModelEntity(mesh: pinMesh, materials: [material])
                
                let pinAnchor = AnchorEntity(world: result.worldTransform)
                pinAnchor.addChild(pinEntity)
                arView.scene.addAnchor(pinAnchor)
                
                // In a full implementation, calculate distance between dropped pins
            }
        }
    }
}
