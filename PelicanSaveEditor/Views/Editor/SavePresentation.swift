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

/// A visible destination label distinguishes leaving the editor from ending text entry.
struct EditorReturnButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            KeyboardReturnAction.dismiss()
            action()
        } label: {
            // A semantic Label is collapsed to its icon by compact toolbars.
            // Keep destination text in an explicit layout so it stays visible.
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text(title)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 44)
        }
        .accessibilityLabel(title)
        .accessibilityHint("保留当前草稿并返回，不会直接写入游戏存档")
    }
}

/// Shared entry point so edits are always one tap away from the complete review.
struct DraftReviewBar: View {
    @Bindable var session: SaveSession
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let message = session.draftValidationMessage {
                Text(message).font(.caption).foregroundStyle(AppTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                KeyboardReturnAction.dismiss()
                onReview()
            } label: {
                GameLabel(
                    session.hasChanges ? "检查 \(session.diffs.count) 项更改并保存" : (session.source.mode == .importedCopy ? "继续导出 / 查看存档" : "查看存档与备份"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(GameButtonStyle(prominent: true))
            .tint(AppTheme.accent)
            .accessibilityIdentifier("editor.review.open")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .readablePageWidth(AppLayout.editorWidth)
        .gameBar()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.review.bar")
    }
}

/// The same quiet step indicator follows the user through review and export.
struct SaveFlowProgress: View {
    let step: Int
    private let titles = ["检查更改", "保存与导出", "完成"]
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(0..<3) { index in
                VStack(spacing: 6) {
                    Text(index + 1 < step ? "✓" : "\(index + 1)")
                        .font(.caption.bold())
                        .frame(width: 26, height: 26)
                        .foregroundStyle(index + 1 <= step ? AppTheme.onAccent : AppTheme.secondary)
                        .background(Circle().fill(index + 1 <= step ? AppTheme.accent : AppTheme.inset))
                    Text(titles[index]).font(.caption)
                        .foregroundStyle(index + 1 == step ? AppTheme.ink : AppTheme.secondary)
                        .multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(step) 步，共 3 步，\(titles[min(2, max(0, step - 1))])")
    }
}

struct SaveFlowActionBar<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 4) { content }
            .font(.headline)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .readablePageWidth(AppLayout.editorWidth)
            .gameBar()
    }
}
