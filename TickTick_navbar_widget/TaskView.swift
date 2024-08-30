import SwiftUI

struct TaskView: View {
    let taskTitle: String
    let timeRemaining: String
    
    var body: some View {
        HStack {
            Text(taskTitle)
            Text("-")
            Text(timeRemaining)
        }
        .padding(.horizontal, 8)
    }
}

// ... preview provider ...