//
//  TickTickAuth.swift
//  TickTick_navbar_widget
//
//  Created by Dani Ifrim on 30/08/2024.
//


import Foundation
import AuthenticationServices
import Security

class TickTickAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = TickTickAuth()
    
    private let clientID = "a9mqAZ17SKjvc9S3sH"
    private let clientSecret = "TB!t@a1u#ik6M#4ln455V&$m)VnsOQLk"
    private let redirectURI = "http://127.0.0.1:8080"
    private let authURL = "https://ticktick.com/oauth/authorize"
    private let tokenURL = "https://ticktick.com/oauth/token"
    
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    
    private var projectColors: [String: String] = [:]
    
    override init() {
        super.init()
        loadAccessTokenFromKeychain()
    }
    
    private func loadAccessTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "TickTickAccessToken",
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess,
           let data = item as? Data,
           let token = String(data: data, encoding: .utf8) {
            self.accessToken = token
            self.isAuthenticated = true
        } else {
            print("Failed to load access token from keychain: \(status)")
        }
    }
    
    private func saveAccessTokenToKeychain(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "TickTickAccessToken",
            kSecValueData as String: token.data(using: .utf8)!
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Item already exists, so let's update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "TickTickAccessToken"
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: token.data(using: .utf8)!
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            if updateStatus != errSecSuccess {
                print("Failed to update access token in keychain: \(updateStatus)")
            }
        } else if status != errSecSuccess {
            print("Failed to save access token to keychain: \(status)")
        }
    }
    
    func authenticate(completion: @escaping (Bool) -> Void) {
        let state = UUID().uuidString
        let authURLString = "\(authURL)?scope=tasks:read%20tasks:write&client_id=\(clientID)&state=\(state)&redirect_uri=\(redirectURI)&response_type=code"
        guard let authURL = URL(string: authURLString) else {
            completion(false)
            return
        }
        
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "http") { callbackURL, error in
            guard error == nil, let callbackURL = callbackURL else {
                print("Authentication failed: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
                return
            }
            
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                print("Couldn't get auth code")
                completion(false)
                return
            }
            
            self.exchangeCodeForToken(code) { success in
                completion(success)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true  // Add this line
        session.start()
        print("Starting authentication...")
    }
    
    private func exchangeCodeForToken(_ code: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: tokenURL) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let credentials = "\(clientID):\(clientSecret)".data(using: .utf8)?.base64EncodedString() ?? ""
        request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        
        let bodyParams = [
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        request.httpBody = bodyParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Token exchange failed: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let accessToken = json["access_token"] as? String {
                    DispatchQueue.main.async {
                        self.accessToken = accessToken
                        self.isAuthenticated = true
                        self.saveAccessTokenToKeychain(accessToken)
                        print("Authentication successful")
                        completion(true)
                    }
                } else {
                    print("Failed to extract access token from response")
                    completion(false)
                }
            } catch {
                print("Failed to parse token response: \(error.localizedDescription)")
                completion(false)
            }
        }.resume()
    }

    private func callTickTick(path: String, httpMethod: String, body: Data? = nil, completion: @escaping (Result<Any, Error>) -> Void) {
        let maxRetries = 3
        let retryDelay: TimeInterval = 1.0
        
        func attempt(retryCount: Int) {
            guard let url = URL(string: "https://api.ticktick.com/open/v1/\(path)") else {
                completion(.failure(NSError(domain: "TickTickAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = httpMethod
            request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            if let body = body {
                request.httpBody = body
            }
            
            print("Making API call to: \(url.absoluteString)")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("API call failed with error: \(error.localizedDescription)")
                    if retryCount < maxRetries {
                        print("Retrying in \(retryDelay) seconds...")
                        DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) {
                            attempt(retryCount: retryCount + 1)
                        }
                    } else {
                        completion(.failure(error))
                    }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(NSError(domain: "TickTickAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                    return
                }
                
                print("HTTP Status Code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 401 {
                    // Token is invalid or expired, we need to re-authenticate
                    self.isAuthenticated = false
                    self.accessToken = nil
                    completion(.failure(NSError(domain: "TickTickAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])))
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    if retryCount < maxRetries {
                        print("Retrying in \(retryDelay) seconds...")
                        DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) {
                            attempt(retryCount: retryCount + 1)
                        }
                    } else {
                        completion(.failure(NSError(domain: "TickTickAuth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error: \(httpResponse.statusCode)"])))
                    }
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "TickTickAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                do {
                    if let jsonResult = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        completion(.success(jsonResult))
                    } else if let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                        completion(.success(jsonArray))
                    } else {
                        print("Unexpected JSON structure: \(String(data: data, encoding: .utf8) ?? "Unable to convert data to string")")
                        completion(.failure(NSError(domain: "TickTickAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])))
                    }
                } catch {
                    print("JSON parsing error: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }.resume()
        }
        
        attempt(retryCount: 0)
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
    
    func fetchAllProjects(completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let path = "project"
        callTickTick(path: path, httpMethod: "GET") { result in
            switch result {
            case .success(let json):
                print("Received JSON: \(json)")
                if let projects = json as? [[String: Any]] {
                    // Store project colors
                    for project in projects {
                        if let id = project["id"] as? String,
                           let color = project["color"] as? String {
                            self.projectColors[id] = color
                        }
                    }
                    completion(.success(projects))
                } else {
                    print("Unexpected JSON structure: \(json)")
                    completion(.failure(NSError(domain: "TickTickAuth", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse projects"])))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchTasksForProject(_ projectId: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let path = "project/\(projectId)/data"
        
        callTickTick(path: path, httpMethod: "GET") { result in
            switch result {
            case .success(let json):
                if let projectData = json as? [String: Any],
                   let tasks = projectData["tasks"] as? [[String: Any]] {
                    completion(.success(tasks))
                } else {
                    print("Unexpected JSON structure for project data: \(json)")
                    completion(.failure(NSError(domain: "TickTickAuth", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse project data"])))
                }
            case .failure(let error):
                completion(.failure(error))
            } 
        }
    }

    func fetchTodayTasks(completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "Europe/Madrid")
        let today = dateFormatter.string(from: Date())
        print("Today's date: \(today)")
        
        fetchAllProjects { result in
            switch result {
            case .success(let projects):
                var todayTasks: [[String: Any]] = []
                let group = DispatchGroup()
                var fetchErrors: [Error] = []
                
                for project in projects {
                    if let projectId = project["id"] as? String {
                        group.enter()
                        self.fetchTasksForProject(projectId) { taskResult in
                            switch taskResult {
                            case .success(let tasks):
                                print("Fetched \(tasks.count) tasks for project \(projectId)")
                                let filteredTasks = tasks.filter { task in
                                    if let startDate = task["startDate"] as? String {
                                        let taskDate = String(startDate.prefix(10))
                                        return taskDate == today
                                    }
                                    return false
                                }
                                print("Filtered \(filteredTasks.count) tasks for today from project \(projectId)")
                                todayTasks.append(contentsOf: filteredTasks)
                            case .failure(let error):
                                print("Failed to fetch tasks for project \(projectId): \(error.localizedDescription)")
                                fetchErrors.append(error)
                            }
                            group.leave()
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    if !fetchErrors.isEmpty {
                        print("Encountered \(fetchErrors.count) errors while fetching tasks")
                        completion(.failure(fetchErrors.first!))
                    } else {
                        print("Total tasks found for today: \(todayTasks.count)")
                        completion(.success(todayTasks))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func getTodayTasks(completion: @escaping (Result<[TaskEntry], Error>) -> Void) {
        print("Fetching tasks for today")

        fetchTodayTasks { result in
            switch result {
            case .success(let tasks):
                print("Successfully fetched \(tasks.count) tasks")
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                let taskEntries = tasks.compactMap { task -> TaskEntry? in
                    guard let id = task["id"] as? String,
                          let title = task["title"] as? String,
                          let projectId = task["projectId"] as? String else {
                        print("Failed to parse task: \(task)")
                        return nil
                    }
                    let isAllDay = task["isAllDay"] as? Bool ?? false
                    var startDate: Date? = nil
                    var endDate: Date? = nil
                    if let startDateString = task["startDate"] as? String {
                        startDate = dateFormatter.date(from: startDateString)
                    }
                    if let endDateString = task["dueDate"] as? String {
                        endDate = dateFormatter.date(from: endDateString)
                    }
                    
                    let projectColor = self.projectColors[projectId] ?? "#CCCCCC"
                    
                    print("Parsed task: \(title), Start: \(startDate?.description ?? "nil"), End: \(endDate?.description ?? "nil"), Color: \(projectColor)")
                    
                    return TaskEntry(id: id, title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay, projectColor: projectColor, projectId: projectId)
                }
                print("Created \(taskEntries.count) TaskEntry objects")
                completion(.success(taskEntries))
            case .failure(let error):
                print("Failed to fetch today's tasks: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    func reAuthenticate(completion: @escaping (Bool) -> Void) {
        self.authenticate { success in
            if success {
                print("Re-authentication successful")
            } else {
                print("Re-authentication failed")
            }
            completion(success)
        }
    }
}
