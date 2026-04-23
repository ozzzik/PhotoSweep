//
//  IndexUnionFind.swift
//  PhotosCleanup
//
//  Disjoint-set union for transitive clustering: if A≈B and B≈C, all three belong
//  in one group even when A≈C is above the pairwise threshold (star-shaped clustering misses this).
//

import Foundation

final class IndexUnionFind: @unchecked Sendable {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    func find(_ i: Int) -> Int {
        if parent[i] != i {
            parent[i] = find(parent[i])
        }
        return parent[i]
    }

    func union(_ i: Int, _ j: Int) {
        var a = find(i)
        var b = find(j)
        if a == b { return }
        if rank[a] < rank[b] {
            parent[a] = b
        } else if rank[a] > rank[b] {
            parent[b] = a
        } else {
            parent[b] = a
            rank[a] += 1
        }
    }
}
