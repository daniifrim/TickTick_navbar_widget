//
//  TickTickMenuBarApp.swift
//  TickTick_navbar_widget
//
//  Created by Dani Ifrim on 30/08/2024.
//

import SwiftUI
import Combine
import AppKit

@main
struct TickTickMenuBarApp: App {
    @StateObject private var viewModel = TaskViewModel()
    @StateObject private var auth = TickTickAuth.shared
    
    var body: some Scene {
        MenuBarExtra {
            if auth.isAuthenticated {
                ContentView(viewModel: viewModel, auth: auth)
            } else {
                VStack {
                    Text("Not logged in")
                        .font(.custom("SF Pro Display", size: 13))
                        .foregroundColor(Color(hexString: "7c7c7c"))
                    Button("Login to TickTick") {
                        auth.authenticate { success in
                            if success {
                                viewModel.updateCurrentTask()
                            }
                        }
                    }
                    .padding()
                }
                .frame(width: 220)
                .background(Color.black)
            }
        } label: {
            if auth.isAuthenticated {
                Text(viewModel.displayText)
                    .foregroundColor(Color(hexString: viewModel.currentTaskColor))
            } else {
                Text("Not logged in")
            }
        }
    }
}

class TaskViewModel: ObservableObject {
    @Published var currentTaskTitle: String = "No task"
    @Published var timeRemaining: String = ""
    @Published var displayText: String = "No task"
    @Published var currentTaskColor: String = "#CCCCCC"
    @Published var upcomingTasks: [TaskEntry] = []
    private var timer: AnyCancellable?
    private var lastSuccessfulFetch: Date?
    
    init() {
        startTimer()
    }
    
    func updateCurrentTask() {
        print("Updating current task")
        TickTickAuth.shared.getTodayTasks { [weak self] result in
            switch result {
            case .success(let tasks):
                DispatchQueue.main.async {
                    self?.processTasks(tasks)
                    self?.lastSuccessfulFetch = Date()
                }
            case .failure(let error):
                print("Failed to fetch today's tasks: \(error.localizedDescription)")
                if (error as NSError).code == 401 {
                    // Re-authenticate if the token is invalid
                    TickTickAuth.shared.reAuthenticate { success in
                        if success {
                            self?.updateCurrentTask() // Retry after re-authentication
                        } else {
                            print("Re-authentication failed")
                        }
                    }
                }
            }
        }
    }
    
    private func processTasks(_ tasks: [TaskEntry]) {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        
        print("Processing \(tasks.count) tasks")
        
        let todayTasks = tasks.filter { task in
            if let taskDate = task.startDate {
                return taskDate >= todayStart && taskDate < todayEnd
            }
            return task.isAllDay
        }.sorted { $0.startDate ?? Date.distantFuture < $1.startDate ?? Date.distantFuture }
        
        print("Tasks for today: \(todayTasks.count)")
        
        for task in todayTasks {
            print("Today's task: \(task.title) at \(task.startDate?.description ?? "All Day") to \(task.endDate?.description ?? "N/A")")
        }
        
        let currentOrUpcomingTasks = todayTasks.filter { task in
            guard let endDate = task.endDate else { return true }
            return endDate > now
        }
        
        if let nextTask = currentOrUpcomingTasks.first {
            self.currentTaskTitle = nextTask.truncatedTitle
            self.timeRemaining = nextTask.remainingTime(from: now)
            self.currentTaskColor = nextTask.projectColor
            self.updateDisplayText()
        } else if currentOrUpcomingTasks.isEmpty && !todayTasks.isEmpty {
            self.currentTaskTitle = "All tasks completed"
            self.timeRemaining = ""
            self.currentTaskColor = "#CCCCCC"
            self.updateDisplayText()
        }
        
        self.upcomingTasks = Array(currentOrUpcomingTasks.dropFirst())
        
        // Print details of upcoming tasks
        for (index, task) in self.upcomingTasks.enumerated() {
            print("Upcoming task \(index + 1): \(task.title) at \(task.startDate?.description ?? "All Day") to \(task.endDate?.description ?? "N/A")")
        }
    }
    
    private func updateDisplayText() {
        if !timeRemaining.isEmpty {
            displayText = "\(currentTaskTitle) • \(timeRemaining)"
        } else {
            displayText = currentTaskTitle
        }
    }
    
    private func startTimer() {
        timer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTimeRemaining()
                self?.updateCurrentTask()
            }
    }
    
    private func updateTimeRemaining() {
        let now = Date()
        if let nextTask = upcomingTasks.first {
            self.timeRemaining = nextTask.remainingTime(from: now)
            self.updateDisplayText()
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: TaskViewModel
    @ObservedObject var auth: TickTickAuth
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming today")
                .font(.custom("SF Pro Display", size: 13))
                .foregroundColor(Color(hexString: "7c7c7c"))
            
            if viewModel.upcomingTasks.isEmpty {
                Text("No upcoming tasks")
                    .font(.custom("SF Pro Display", size: 13))
                    .foregroundColor(Color(hexString: "e6e7e7"))
            } else {
                ForEach(viewModel.upcomingTasks, id: \.id) { task in
                    TaskEntryView(task: task)
                }
            }
            
            Divider()
            
            Button(action: {
                openTickTick()
            }) {
                Label("Open TickTick", systemImage: "arrow.up.right.square")
            }
            
            Button(action: {
                viewModel.updateCurrentTask()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            
            Button("Logout") {
                auth.isAuthenticated = false
                auth.accessToken = nil
            }
        }
        .padding()
        .frame(width: 220)
        .background(Color.black)
        .onAppear {
            print("ContentView appeared")
            viewModel.updateCurrentTask()
        }
    }
    
    private func openTickTick() {
        let workspace = NSWorkspace.shared
        let tickTickBundleIdentifier = "com.ticktick.task.mac"
        
        if let url = workspace.urlForApplication(withBundleIdentifier: tickTickBundleIdentifier) {
            workspace.open(url)
        } else {
            // If the app is not installed, open the TickTick website
            if let url = URL(string: "https://ticktick.com") {
                workspace.open(url)
            }
        }
    }
}

struct TaskEntryView: View {
    let task: TaskEntry
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(task.formattedString)
                .font(.custom("SF Pro Display", size: 13))
                .foregroundColor(Color(hexString: task.projectColor))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .background(isHovered ? Color(hexString: "315FC4") : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            openTaskInBrowser()
        }
        .help(task.title)
    }
    
    private func openTaskInBrowser() {
        let workspace = NSWorkspace.shared
        let tickTickBundleIdentifier = "com.ticktick.task.mac"
        
        if let url = workspace.urlForApplication(withBundleIdentifier: tickTickBundleIdentifier) {
            // Assuming the desktop app supports a URL scheme to open specific tasks
            if let taskURL = URL(string: "ticktick://task/\(task.id)") {
                workspace.open(taskURL)
            }
        } else {
            // Fallback to web if the desktop app is not installed
            if let url = URL(string: "https://ticktick.com/webapp/#q/today/tasks/\(task.id)") {
                workspace.open(url)
            }
        }
    }
}
struct TaskEntry: Identifiable {
    let id: String
    let title: String
    let startDate: Date?
    let endDate: Date?
    let isAllDay: Bool
    let projectColor: String
    let projectId: String
    
    var truncatedTitle: String {
        if title.count > 25 {
            return String(title.prefix(20)) + "..."
        }
        return title
    }
    
    var formattedString: String {
        if let startDate = startDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: startDate)) • \(truncatedTitle)"
        } else {
            return "All Day • \(truncatedTitle)"
        }
    }
    
    func remainingTime(from currentDate: Date) -> String {
        guard let startDate = startDate, let endDate = endDate else {
            return isAllDay ? "All Day" : ""
        }
        
        let timeUntilStart = startDate.timeIntervalSince(currentDate)
        let timeUntilEnd = endDate.timeIntervalSince(currentDate)
        
        if timeUntilStart > 0 {
            return "in \(formatTimeInterval(timeUntilStart))"
        } else if timeUntilEnd > 0 {
            if timeUntilStart > -300 { // Within first 5 minutes of task
                return "now"
            } else {
                return "\(formatTimeInterval(timeUntilEnd)) left"
            }
        } else {
            return "ended"
        }
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

extension Color {
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
