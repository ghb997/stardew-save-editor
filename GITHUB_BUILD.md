# GitHub Actions 生成 IPA

当前版本为 0.7.0（构建 15），修复源码位于 `codex/complete-repair-build15` 分支。对应的 Release arm64 IPA 已构建，详见 [构建任务](https://github.com/ghb997/stardew-save-editor/actions/runs/34688577632)。测试范围、原始结果与源码对应关系见 [构建 15 验证记录](validation/BUILD15_VERIFICATION.md)。

仓库的 Actions 工作流使用 GitHub 托管的 macOS 构建机、Xcode 和 iPhoneOS SDK 编译 Release 应用，然后以 `Payload/SheaflightAmberVault.app` 结构打包 IPA。

此流程产出供后续签名使用的 unsigned IPA。它不包含 Apple 开发者证书或 provisioning profile，不能仅靠下载文件直接安装到普通 iPhone；安装前需要通过自己的签名/侧载工具签名。不要把 Apple 密码、证书或私钥提交到仓库。

## 生成与下载

1. 在 Actions 中选择构建 IPA 的工作流，点击 Run workflow 并选择 `codex/complete-repair-build15` 分支；该分支的普通源码推送也会自动触发工作流。带 `[skip ci]` 的证据提交不触发自动构建。
2. 等待构建成功，打开该次运行页下方的 Artifacts。
3. 下载 IPA 构建产物并解压。产物包括 IPA、SHA-256 与构建信息；构建日志另存为诊断产物。

编译失败时会保留日志。工作流仅拥有读取仓库内容的权限，不创建公开 Release，也不要求配置 Apple secrets。

## 验证边界

工作流验证 iPhoneOS/arm64 构建、应用 Info.plist、可执行文件以及 IPA 包结构。生成 IPA 不代表已经通过真实游戏读档测试或所有 UI 流程验收。现有 XCTest 与模拟器验证可在 Mac 上运行 `bash scripts/validate-on-macos.sh`。

在 Actions 的 `Verify Tracker native UI` 中，`test_scope=full` 执行完整 173 项方法；`test_scope=repair` 只执行装备与收藏的 4 条修复 UI 流程。`capture_screenshots=false` 可省略测试结束后的独立展示截图，XCTest 内保存的原生截图仍随测试附件交付。运行状态和具体结果需要单独核对，部分范围通过不能把另一轮失败任务标记为成功。
