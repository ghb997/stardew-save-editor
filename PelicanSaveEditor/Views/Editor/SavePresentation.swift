import SwiftUI

extension SaveAccessMode {
    var displayName: String {
        switch self {
        case .directory: "农场目录"
        case .twoFiles: "原位双文件"
        case .importedCopy: "复制导入副本"
        }
    }

    var saveExplanation: String {
        switch self {
        case .directory, .twoFiles:
            "保存会先备份原文件，再校验来源是否变化并写回。请在保存前完全退出游戏。"
        case .importedCopy:
            "编辑的是应用内副本。保存后还需导出到游戏原农场目录，并替换同名存档文件。"
        }
    }
}

extension FarmEntity {
    var coordinateDescription: String {
        guard let tileX, let tileY else { return "无坐标记录" }
        return "X \(tileX.formatted(.number.precision(.fractionLength(0...2)))) · Y \(tileY.formatted(.number.precision(.fractionLength(0...2))))"
    }
}

extension SaveSession {
    var draftValidationMessage: String? {
        do {
            try SaveMutator.validate(draft, comparedTo: originalDraft)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// Shared entry point so edits are always one tap away from the complete review.
struct DraftReviewBar: View {
    @Bindable var session: SaveSession
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let message = session.draftValidationMessage {
                Text(message).font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onReview) {
                GameLabel(
                    session.hasChanges ? "检查 \(session.diffs.count) 项更改并保存" : "查看存档与备份",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .accessibilityIdentifier("editor.review.open")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.review.bar")
    }
}
