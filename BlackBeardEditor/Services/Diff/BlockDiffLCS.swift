import Foundation

/// LCS on block fingerprints (separate from word-level `DiffLCS`).
enum BlockDiffLCS {
    enum Op {
        case equal(Int)
        case delete(Int)
        case insert(Int)
    }

    static func diff(old: [String], new: [String]) -> [Op] {
        if old.isEmpty { return new.isEmpty ? [] : [.insert(new.count)] }
        if new.isEmpty { return [.delete(old.count)] }

        let n = old.count, m = new.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var raw: [Op] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, old[i - 1] == new[j - 1] {
                raw.append(.equal(1))
                i -= 1; j -= 1
            } else if j > 0, (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                raw.append(.insert(1))
                j -= 1
            } else {
                raw.append(.delete(1))
                i -= 1
            }
        }

        return raw.reversed().reduce(into: [Op]()) { result, op in
            merge(&result, op)
        }
    }

    private static func merge(_ result: inout [Op], _ op: Op) {
        guard let last = result.last else {
            result.append(op)
            return
        }
        switch (last, op) {
        case (.equal(let a), .equal(let b)): result[result.count - 1] = .equal(a + b)
        case (.delete(let a), .delete(let b)): result[result.count - 1] = .delete(a + b)
        case (.insert(let a), .insert(let b)): result[result.count - 1] = .insert(a + b)
        default: result.append(op)
        }
    }
}
