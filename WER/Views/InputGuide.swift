//
//  InputGuide.swift
//  WER
//

import SwiftUI

/// Rename 입력칸에 커서가 있을 때 Order 칸 위에 띄우는 입력 안내 (설정 > General > Show Input Guide).
/// 칸들이 각자 잘려(clipped) 있어서, TokenGridEditor가 위치를 올려 보내고 ContentView가 칸들 위에 그린다
struct InputGuideField {
    let token: NameToken
    let slot: Int
    /// -1 종류 드롭다운, 0 첫 칸, 1 두 번째 칸, 2 구분자
    let column: Int
    let isOmittedSeparator: Bool
    /// 확장자 대상 겹침 오류
    let conflict: String?
}

/// 커서가 있는 줄의 손잡이 위치와 안내할 칸
struct InputGuideAnchor {
    let anchor: Anchor<CGRect>
    let field: InputGuideField
}

struct InputGuideKey: PreferenceKey {
    static var defaultValue: InputGuideAnchor? { nil }

    static func reduce(value: inout InputGuideAnchor?, nextValue: () -> InputGuideAnchor?) {
        value = value ?? nextValue()
    }
}

/// 안내 풍선 배치. 줄 왼쪽(Order 칸 위)에 꼬리를 줄로 향하게 두고, 왼쪽이 좁으면 줄 아래에 둔다
struct InputGuideOverlay: View {
    let rect: CGRect
    let size: CGSize
    let field: InputGuideField

    private static let maxWidth: CGFloat = 320
    private static let minBesideWidth: CGFloat = 220
    private static let gap: CGFloat = 10

    var body: some View {
        let besideSpace = rect.minX - Self.gap - 8
        let isBeside = besideSpace >= Self.minBesideWidth
        let width = isBeside
            ? min(Self.maxWidth, besideSpace)
            : max(min(Self.maxWidth, size.width - rect.minX - 8), 160)
        // 뾰족한 위 모서리가 줄 가운데(옆) 또는 손잡이(아래)를 가리킨다
        let origin = isBeside
            ? CGPoint(x: rect.minX - Self.gap - width, y: max(rect.midY - 2, 4))
            : CGPoint(x: rect.minX, y: rect.maxY + Self.gap)
        InputGuideBubble(field: field, corner: isBeside ? .topTrailing : .topLeading)
            .frame(width: width, alignment: .leading)
            .frame(maxHeight: max(size.height - origin.y - 8, 60), alignment: .top)
            .offset(x: origin.x, y: origin.y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}

struct InputGuideBubble: View {
    let field: InputGuideField

    /// Rename 쪽을 가리키는 뾰족한 모서리
    let corner: GuideBubbleShape.Corner
    /// 팝오버 안에 넣을 때는 풍선 배경·외곽선·그림자 없이 내용만 그린다 (설정의 프리셋 편집, 시험용)
    var isPlain = false

    private var token: NameToken { field.token }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))
            if let error {
                Label(error, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(description)
                .foregroundStyle(.secondary)
            if field.column == 0, token.kind.isDate {
                DateFormatTable()
            } else if field.column == 0, token.kind == .regex {
                RegexExamples()
            } else if field.column == 1, token.kind == .regex {
                GuideExamples(rows: [
                    ("0000", "pad to 4 digits: 12 → 0012"),
                    ("$2", "group 2"),
                    ("$2:000", "group 2, 3 digits"),
                    ("$0", "whole match"),
                ])
            } else if token.kind == .replace {
                GuideExamples(rows: field.column == 0 ? [
                    (#"\s+"#, "spaces"),
                    ("^IMG_", "IMG_ at the start"),
                    (#"(\d{4})(\d{2})(\d{2})"#, "date digits as groups"),
                    (#"^(.+)_(.+)$"#, "two parts around the last _"),
                ] : [
                    ("-", "replace with -"),
                    ("(empty)", "delete the matches"),
                    ("$1-$2-$3", "insert groups"),
                    ("$2_$1", "swap two parts"),
                ])
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(BubbleChrome(corner: corner, color: RegexPalette.color(field.slot), isPlain: isPlain))
    }

    private var fieldName: String {
        switch field.column {
        case -1: return "Type"
        case 2: return "Separator"
        default: break
        }
        let names: (String, String?) = switch token.kind {
        case .none: ("Value", nil)
        case .text: ("Text", "Suffix")
        case .number: ("Start", "Step")
        case .regex: ("Pattern", "Group / Pad")
        case .replace: ("Pattern", "Replace with")
        case .createdDate, .modifiedDate, .takenDate: ("Format", "If not found")
        case .changeExtension: ("Extension", "New extension")
        case .removeExtension, .addExtension: ("Extension", nil)
        }
        return (field.column == 0 ? names.0 : names.1) ?? "Not used"
    }

    private var title: String {
        "Slot \(field.slot + 1) · \(TokenGridEditor.title(for: token.kind)) · \(fieldName)"
    }

    /// 형식 오류(빨강). 빈 칸은 주황 경고로 보여준다
    private var error: String? {
        let message = switch field.column {
        case 0: token.validationError ?? field.conflict
        case 1: token.optionError
        case 2: token.separatorError
        default: String?.none
        }
        return message == NameToken.emptyValueMessage ? nil : message
    }

    private var warning: String? {
        switch field.column {
        case 0: token.needsValue ? NameToken.emptyValueMessage : token.valueWarning
        case 1: token.needsOption ? NameToken.emptyValueMessage : token.warning
        default: nil
        }
    }

    private var description: String {
        switch field.column {
        case -1:
            let shortcut = "⌘\(field.slot + 1) opens this menu."
            return token.kind == .none
                ? "\(shortcut) Choose what this slot adds to the new name"
                : "\(shortcut) \(TokenGridEditor.help(for: token.kind))"
        case 0: return TokenGridEditor.help(for: token.kind)
        case 1: return TokenGridEditor.optionHelp(for: token.kind)
        default:
            return field.isOmittedSeparator
                ? "Omitted after the last slot"
                : "Added after this slot's value. Empty: no separator"
        }
    }
}

/// 말풍선. 한 위 모서리만 바깥으로 뾰족하게 늘이고 나머지는 둥글다.
/// topTrailing은 오른쪽(Rename 칸)으로, topLeading은 위(입력 줄)로 뻗는다
private struct BubbleChrome: ViewModifier {
    let corner: GuideBubbleShape.Corner
    let color: Color
    let isPlain: Bool

    func body(content: Content) -> some View {
        if isPlain {
            content
        } else {
            content
                .background(.regularMaterial, in: GuideBubbleShape(corner: corner))
                // 외곽선은 칸 손잡이 색 (Order 표의 조각 강조 색과 같다)
                .overlay(GuideBubbleShape(corner: corner).stroke(color, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
    }
}

nonisolated struct GuideBubbleShape: Shape {
    enum Corner { case topTrailing, topLeading }

    let corner: Corner
    var radius: CGFloat = 8
    /// 뾰족한 끝이 모서리 밖으로 나가는 길이
    var tip: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        return Path { path in
            switch corner {
            case .topTrailing:
                path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX + tip, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tip * 1.6))
                path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                            tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
                path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                            tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
                path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                            tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
            case .topLeading:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY - tip))
                path.addLine(to: CGPoint(x: rect.minX + tip * 1.6, y: rect.minY))
                path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
                path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                            tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
                path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                            tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
            }
            path.closeSubpath()
        }
    }
}

/// 날짜 형식 글자 표. 예시는 2024-05-01 13:22:10
private struct DateFormatTable: View {
    private static let sample = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2024, month: 5, day: 1, hour: 13, minute: 22, second: 10)
    ) ?? .now

    private static let rows: [(String, String)] = [
        ("yyyy", "year"), ("yy", "year, 2 digits"), ("MM", "month"), ("dd", "day"),
        ("HH", "hour 00-23"), ("hh a", "hour 01-12, AM/PM"), ("mm", "minute"), ("ss", "second"),
        ("E", "weekday"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 1) {
                ForEach(Self.rows, id: \.0) { letters, meaning in
                    GridRow {
                        Text(letters).monospaced()
                        Text(DateFormat.string(from: Self.sample, format: letters)).monospaced()
                        Text(meaning).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Avoid YYYY (week-based year) and DD (day of the year)")
                .foregroundStyle(.secondary)
        }
    }
}

private struct RegexExamples: View {
    private static let rows: [(String, String)] = [
        (#"\d+"#, "first number"),
        (#"IMG_(\d+)"#, "digits after IMG_"),
        (#"(?:IMG_)(\d+)_(\d+)"#, "(?:) isn't a group: $1, $2 are the numbers"),
        (#"^([^_]+)"#, "text before the first _"),
        (#"(\d{8})"#, "8 digits, e.g. 20240501"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 1) {
            ForEach(Self.rows, id: \.0) { pattern, meaning in
                GridRow {
                    Text(pattern).monospaced()
                    Text(meaning).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 입력 예시 표 (패턴 또는 값, 뜻)
private struct GuideExamples: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 1) {
            ForEach(rows, id: \.0) { example, meaning in
                GridRow {
                    Text(example).monospaced()
                    Text(meaning).foregroundStyle(.secondary)
                }
            }
        }
    }
}
