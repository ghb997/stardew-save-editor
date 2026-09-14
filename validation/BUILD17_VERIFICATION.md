# 鹈鹕修改器 0.8.1 · 构建 17 验证记录

## 当前交付

- 应用名称：鹈鹕修改器。
- 对应构建及测试提交：`1f45a4ad86dd0e12f3b68df2adcc17be343b2ead`。
- 修复范围：复制导入时，系统文件选择回调与 SwiftUI 弹窗关闭回调顺序不固定，造成第一次选择可能未被消费。
- Release arm64 编译：通过。Xcode 16.4，iOS SDK 18.5，最低 iOS 17，支持 iPhone 与 iPad。
- 安装包：`PelicanEditor-v0.8.1-build17-unsigned.ipa`，3,732,645 字节。
- IPA SHA-256：`64930b08746b353b05186bf283259826ff1683123858b9608624be41f3680f22`。
- ZIP 完整性、设备 Mach-O、版本、显示名称、设备家族及编译图标核对通过。
- 安装包未签名，需要使用自己的签名工具及签名资料安装。

## 修复与回归验证

导入流程现在同时等待文件选择和弹窗关闭两个信号。两个信号无论谁先到，URL 都会在本次操作中消费一次；取消会清空当次状态。新增并实际执行以下回归测试：

- `testCopyImportSelectionBeforeDismissalIsConsumedOnce`
- `testCopyImportDismissalBeforeSelectionIsConsumedOnce`
- `testCopyImportCancellationDoesNotLeakSelectionIntoNextPresentation`

## 原生验证

| 设备 | 系统 | 通过 | 失败 | 跳过 |
| --- | --- | ---: | ---: | ---: |
| iPhone SE (3rd generation) | iOS 26.2 模拟器 | 159 | 0 | 0 |
| iPad mini (A17 Pro) | iOS 26.2 模拟器 | 6 | 0 | 0 |

iPhone 作业包含全部单元测试及本轮 6 项 UI 测试；iPad mini 作业包含本轮 6 项 UI 测试。逐项报告与精确提交中的测试声明核对，没有缺失、重复或意外测试。相较构建 16，iPhone 通过数由 156 增至 159，增量正好对应上述 3 项回归测试。

已审阅 iPhone 与 iPad mini 的 4 张导入相关原生截图，确认唯一复制导入入口和系统文件选择器在两类设备上显示正常。此次没有修改视觉生产代码。

## 来源与可复核证据

- [设备 Release 构建](https://github.com/ghb997/stardew-save-editor/actions/runs/34820047235)
- [iPhone / iPad 原生测试](https://github.com/ghb997/stardew-save-editor/actions/runs/34820047252)
- [对应源码提交](https://github.com/ghb997/stardew-save-editor/commit/1f45a4ad86dd0e12f3b68df2adcc17be343b2ead)

本地辅助检查解析了 93 个 Swift 文件的语法、全部资源引用及 Xcode 源文件注册。6 项静态发布检查通过，覆盖版本、工程结构、文档格式、115 张位图的尺寸、哈希和资源目录。

## 实际验证边界

原生回归测试验证了两种回调顺序、取消清理、复制存档解析和应用内独立副本。模拟器文件选择器测试验证打开、取消和重新打开，但没有在模拟器 Files 中注入用户的真实两份存档，因此未执行真实文件选择端到端复现。尚未验证签名真机安装及真实游戏中的载入、睡觉保存和重新载入往返。
