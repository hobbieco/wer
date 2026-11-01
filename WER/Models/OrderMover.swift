//
//  OrderMover.swift
//  WER
//

import Foundation

nonisolated enum OrderMover {
    /// 선택 항목을 offset만큼 이동한다(음수는 위로).
    /// 선택 항목 사이 간격은 유지하고, 끝에 닿은 항목은 멈춰 뒤따르는 항목이 붙는다.
    static func move<T>(_ items: [T], selected: IndexSet, by offset: Int) -> (items: [T], selected: IndexSet) {
        let picked = selected.filter { items.indices.contains($0) }.sorted()
        guard !picked.isEmpty, offset != 0 else { return (items, IndexSet(picked)) }

        var targets = [Int](repeating: 0, count: picked.count)
        if offset < 0 {
            var floor = 0
            for (i, index) in picked.enumerated() {
                targets[i] = max(index + offset, floor)
                floor = targets[i] + 1
            }
        } else {
            var ceiling = items.count - 1
            for (i, index) in picked.enumerated().reversed() {
                targets[i] = min(index + offset, ceiling)
                ceiling = targets[i] - 1
            }
        }

        var result = [T?](repeating: nil, count: items.count)
        for (i, index) in picked.enumerated() {
            result[targets[i]] = items[index]
        }
        let pickedSet = Set(picked)
        var rest = items.indices.filter { !pickedSet.contains($0) }.map { items[$0] }.makeIterator()
        for slot in result.indices where result[slot] == nil {
            result[slot] = rest.next()
        }
        return (result.compactMap { $0 }, IndexSet(targets))
    }

    /// 연속 선택 구간마다 그 안에서만 뒤집는다. 구간 위치와 선택하지 않은 항목은 그대로.
    /// 두 개 이상 이어진 구간이 없으면(선택 없음, 한 줄씩 떨어진 선택) 뒤집을 게 없으므로 전체를 뒤집는다.
    static func reverse<T>(_ items: [T], selected: IndexSet) -> [T] {
        let valid = selected.filteredIndexSet { items.indices.contains($0) }
        guard valid.rangeView.contains(where: { $0.count > 1 }) else { return items.reversed() }
        var result = items
        for range in valid.rangeView {
            result.replaceSubrange(range, with: items[range].reversed())
        }
        return result
    }

    /// 새 항목을 reference(Select 목록) 순서에 맞춰 order 사이에 끼워 넣는다.
    /// reference에서 바로 앞의 가장 가까운 항목 뒤에, 없으면 맨 앞에 넣는다.
    static func insert<T: Hashable>(_ newItems: [T], into order: [T], reference: [T]) -> [T] {
        var result = order
        var present = Set(order)
        let referenceIndex = Dictionary(reference.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        // reference 순서로 처리해야 연속으로 추가한 항목이 서로 붙는다
        let sorted = newItems
            .filter { !present.contains($0) }
            .sorted { (referenceIndex[$0] ?? .max) < (referenceIndex[$1] ?? .max) }

        for item in sorted {
            defer { present.insert(item) }
            guard let index = referenceIndex[item] else {
                result.append(item)
                continue
            }
            if let before = reference[..<index].last(where: present.contains),
               let position = result.firstIndex(of: before) {
                result.insert(item, at: position + 1)
            } else {
                result.insert(item, at: 0)
            }
        }
        return result
    }
}
