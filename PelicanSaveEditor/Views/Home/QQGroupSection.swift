import SwiftUI
import UIKit

private enum QQCommunity {
    static let number = "719471525"
    static let image = "QQGroupQRCode"
}

struct QQGroupSection: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingQRCode = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("交流与反馈").font(.headline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                Label("星露谷物语 QQ 群", systemImage: "person.3.fill").font(.headline)
                Text("分享农场、交流使用问题与建议。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("群号：\(QQCommunity.number)").font(.title3.bold().monospacedDigit())
                    .textSelection(.enabled).accessibilityIdentifier("settings.qq.number")
                Button {
                    UIPasteboard.general.string = QQCommunity.number
                    copied = true
                    UIAccessibility.post(notification: .announcement, argument: "QQ群号已复制")
                } label: {
                    Group {
                        if typeSize.isAccessibilitySize {
                            Text("复制群号")
                        } else {
                            Label("复制群号", systemImage: "doc.on.doc")
                        }
                    }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                .accessibilityValue(copied ? "已复制群号" : "")
                .accessibilityIdentifier("settings.qq.copy")
                if copied {
                    Text("已复制群号")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.qq.copied")
                }
                Button { showingQRCode = true } label: {
                    Image(QQCommunity.image).resizable().scaledToFit()
                        .frame(maxWidth: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("放大QQ群二维码")
                .accessibilityIdentifier("settings.qq.qrcode")
                Text("使用 QQ 扫码加入，点击图片可放大或分享。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(18).appCard()
        }
        .sheet(isPresented: $showingQRCode) { QQGroupQRCodeView() }
    }
}

private struct QQGroupQRCodeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("群号：\(QQCommunity.number)")
                        .font(.title3.bold()).textSelection(.enabled)
                    Image(QQCommunity.image).resizable().scaledToFit()
                        .frame(maxWidth: 560)
                        .accessibilityLabel("星露谷物语QQ群二维码，群号719471525")
                        .accessibilityIdentifier("settings.qq.fullImage")
                    ShareLink(item: Image(QQCommunity.image),
                              preview: SharePreview("星露谷物语 QQ 群 \(QQCommunity.number)",
                                                    image: Image(QQCommunity.image))) {
                        Label("分享或保存二维码", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                    .accessibilityIdentifier("settings.qq.share")
                }
                .padding(20).readablePageWidth(600)
            }
            .background(AppTheme.canvas)
            .navigationTitle("QQ群二维码").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("settings.qq.close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#if DEBUG
        .modifier(DebugLayoutViewport())
#endif
    }
}
