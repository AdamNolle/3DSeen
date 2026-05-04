import SwiftUI
import ARKit

struct LandscapeCaptureEngine: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    
    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Image(systemName: "mountain.2")
                        .font(.system(size: 24))
                    Text("Landscape VIO")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 10)
                
                Spacer()
                
                Text("LiDAR disabled. Using VIO for outdoor performance.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .padding(.bottom, 20)
                
                Button(action: {
                    stateMachine.send(.finishCapture(scanDataURL: URL(fileURLWithPath: NSTemporaryDirectory())))
                }) {
                    Text("Finish Landscape Scan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.9))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: .orange.opacity(0.3), radius: 10, y: 5)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}
