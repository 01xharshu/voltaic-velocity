import Foundation

struct AIInteractionFeedback: Codable, Equatable {
    let query: String
    let response: String
    let isPositive: Bool
    let timestamp: Date
}

final class FeedbackService {
    static let shared = FeedbackService()
    
    private let maxStoredFeedbacks = 20
    private let defaultsKey = "AIInteractionFeedbackStorage"
    
    private init() {}
    
    func saveFeedback(query: String, response: String, isPositive: Bool) {
        var feedbacks = getFeedbacks()
        let newFeedback = AIInteractionFeedback(query: query, response: response, isPositive: isPositive, timestamp: Date())
        
        feedbacks.insert(newFeedback, at: 0)
        if feedbacks.count > maxStoredFeedbacks {
            feedbacks = Array(feedbacks.prefix(maxStoredFeedbacks))
        }
        
        if let data = try? JSONEncoder().encode(feedbacks) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
    
    func getFeedbacks() -> [AIInteractionFeedback] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let feedbacks = try? JSONDecoder().decode([AIInteractionFeedback].self, from: data) else {
            return []
        }
        return feedbacks
    }
    
    func generateSystemPromptAdditions() -> String {
        let feedbacks = getFeedbacks()
        guard !feedbacks.isEmpty else { return "" }
        
        let liked = feedbacks.filter { $0.isPositive }.prefix(3)
        let disliked = feedbacks.filter { !$0.isPositive }.prefix(3)
        
        var prompt = "\n\n### USER PREFERENCES (LEARNED FROM FEEDBACK) ###\n"
        
        if !liked.isEmpty {
            prompt += "The user explicitly LIKED these patterns in the past. Emulate this style:\n"
            for (index, f) in liked.enumerated() {
                prompt += "Good Example \(index + 1):\nResponse: \(f.response)\n"
            }
        }
        
        if !disliked.isEmpty {
            prompt += "\nThe user explicitly DISLIKED these patterns. DO NOT DO THIS:\n"
            for (index, f) in disliked.enumerated() {
                prompt += "Bad Example \(index + 1):\nResponse: \(f.response)\n"
            }
        }
        
        return prompt
    }
}
