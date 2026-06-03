import Foundation

// MARK: - SensitiveDetector
//
// Heuristic detection of sensitive content pasted from the clipboard.
// Runs on every clip inserted into ClipStore to auto-tag sensitive items.
//
// Patterns are conservative — tuned to minimise false positives while catching
// real credentials. The user can always toggle sensitivity manually with ⌘S.
//
// All patterns are anchored or require specific surrounding characters so that
// ordinary prose does not trigger tagging.

public enum SensitiveDetector {

    private static let patterns: [NSRegularExpression] = {
        let sources: [String] = [
            // ── Payment / identity ────────────────────────────────────────────
            // Credit / debit cards: 4×4 digit groups with optional space or dash
            #"\b(?:\d{4}[\s\-]){3}\d{4}\b"#,
            // US Social Security Number
            #"\b\d{3}-\d{2}-\d{4}\b"#,

            // ── Cryptographic material ─────────────────────────────────────────
            // PEM private keys
            #"-----BEGIN .{0,30}PRIVATE KEY-----"#,
            // PEM certificates (less sensitive but still notable)
            #"-----BEGIN CERTIFICATE-----"#,

            // ── Cloud / SaaS tokens ────────────────────────────────────────────
            // AWS access key IDs
            #"\bAKIA[0-9A-Z]{16,}\b"#,
            // GitHub personal access tokens (classic and fine-grained)
            #"\bgh[pousra]_[A-Za-z0-9]{36,}\b"#,
            // Stripe live/test secret keys
            #"\bsk_(live|test)_[A-Za-z0-9]{24,}\b"#,
            // Slack bot / user / app tokens
            #"\bxox[baprs]-[A-Za-z0-9\-]{10,}"#,
            // Anthropic API keys
            #"\bsk-ant-[A-Za-z0-9\-_]{20,}\b"#,
            // OpenAI API keys
            #"\bsk-[A-Za-z0-9]{20,}\b"#,
            // Generic service account JSON snippet
            #"\"private_key\"\s*:\s*\"-----BEGIN"#,

            // ── Generic credential patterns ────────────────────────────────────
            // key=<long value> or key: <long value> in any case
            #"(?i)(?:api[_\-]?key|api[_\-]?secret|client[_\-]?secret|access[_\-]?token|auth[_\-]?token|bearer[_\-]?token)\s*[=:]\s*[\"']?[A-Za-z0-9+/=_\-]{20,}"#,
            // Authorization: Bearer <token>
            #"(?i)\bauthorization\s*:\s*bearer\s+[A-Za-z0-9+/=_\-\.]{20,}"#,
        ]
        return sources.compactMap {
            try? NSRegularExpression(pattern: $0, options: [])
        }
    }()

    /// Returns `true` if `content` matches any known sensitive credential pattern.
    public static func looksLike(_ content: String) -> Bool {
        // Skip very short strings — too many false positives.
        // 10 is the practical floor: SSNs are 11 chars, but we want headroom for
        // strings with surrounding whitespace that get trimmed by NSRange matching.
        guard content.count >= 10 else { return false }
        let range = NSRange(content.startIndex..., in: content)
        return patterns.contains { $0.firstMatch(in: content, range: range) != nil }
    }
}
