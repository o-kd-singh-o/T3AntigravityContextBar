import Foundation

struct SnapshotDTO: Codable {
    let timestamp: String
    let overall_status: String
    let overall_color_hex: String
    let menu_bar_title: String
    let config: ConfigDTO
    let active_thread: ThreadDTO?
    let threads: [ThreadDTO]
}

struct ConfigDTO: Codable {
    let warn_threshold: Int
    let max_threshold: Int
    let poll_interval_seconds: Int
}

struct ThreadDTO: Codable {
    let thread_id: String
    let title: String
    let status: String
    let updated_at: String
    let session_id: String?
    let metrics: MetricsDTO?
}

struct MetricsDTO: Codable {
    let total_prompt_tokens: Int
    let cached_tokens: Int
    let uncached_tokens: Int
    let completion_tokens: Int
    let thought_tokens: Int
    let percentage: Double
    let remaining_tokens: Int
    let cache_ratio: Double
    let status_level: String
    let color_hex: String
    let formatted_tokens: String
    let recommendation: String
}
