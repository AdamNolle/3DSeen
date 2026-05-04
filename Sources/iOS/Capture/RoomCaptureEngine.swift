import SwiftUI
import RoomPlan

struct RoomCaptureEngine: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    
    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Image(systemName: "house")
                        .font(.system(size: 24))
                    Text("Space Capture")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 10)
                
                Spacer()
                
                Text("Pan the device across walls, windows, and furniture.")
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
                    Text("Finish Space Scan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.9))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: .green.opacity(0.3), radius: 10, y: 5)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}
