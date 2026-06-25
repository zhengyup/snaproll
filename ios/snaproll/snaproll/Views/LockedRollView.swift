import SwiftUI

struct LockedRollView: View {
    let roll: Roll

    var body: some View {
        ContentUnavailableView(
            "Roll Locked",
            systemImage: "lock.fill",
            description: Text("Photos in \(roll.name) stay hidden until every exposure has been used.")
        )
        .navigationTitle("Locked Roll")
    }
}

struct LockedRollView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LockedRollView(roll: .placeholder)
        }
    }
}
