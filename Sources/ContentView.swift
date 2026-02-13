import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "play.circle.fill")
        .resizable()
        .scaledToFit()
        .frame(width: 56, height: 56)
        .foregroundStyle(.blue)

      Text("JustPlay Native")
        .font(.title)
        .fontWeight(.semibold)

      Text("Your macOS app generated with XcodeGen.")
        .foregroundStyle(.secondary)
    }
    .padding(32)
    .frame(minWidth: 420, minHeight: 280)
  }
}
