# 安装包大小对照

2026-09-12，只读检查用户提供的三个 IPA 和构建 15 的 Release IPA。下表使用 MiB（1 MiB = 1,048,576 字节），展开大小为 ZIP 目录中各文件原始大小之和。未运行参考应用，未从中复制代码或资源。

| 应用 | IPA 文件 | 展开后的文件总量 |
| --- | ---: | ---: |
| StardewEditor | 103.06 MiB | 102.76 MiB |
| StardewGuide&Tracker | 58.79 MiB | 58.16 MiB |
| StardewSaveEditor | 40.12 MiB | 40.03 MiB |
| 穗光琥珀存档匣 0.7.0（15） | 3.53 MiB | 12.13 MiB |

三个参考 IPA 的成员采用未压缩存储，IPA 大小还包含 ZIP 目录等开销，因此会略大于展开后的文件总量。本项目的 IPA 使用压缩打包；仅主程序就从约 9.82 MiB 压缩到约 2.28 MiB。这解释了一部分表面差距。比较功能规模时，应同时查看展开大小。

其余差距来自代码、依赖和资源：

- StardewEditor 内置 Flutter、App.framework 和多项第三方框架。最大的三个文件分别约 14.15、11.53 和 8.37 MiB。
- StardewGuide&Tracker 的主程序约 24.94 MiB，另有约 4.40 MiB 的机器学习模型权重、地图和其他资源。仅凭文件存在无法证明其具体运行用途。
- StardewSaveEditor 包含约 7.60 MiB 的 JavaScript 包、约 5.52 MiB 的主程序和约 3.14 MiB 的 Hermes 框架。
- 本项目使用系统提供的 SwiftUI、Foundation 等框架，没有在包内附带第三方运行库。打包资源以物品目录和 113 张位图为主；Assets.car 约 1.32 MiB，物品目录压缩后约 0.07 MiB。

因此，体积小本身不是缺陷，也不能证明功能齐全。构建 15 修复存档写入问题并补充已有装备属性编辑、收藏与缺失清单；高级预测、完整地形/人物渲染、完整锻造及全部多人/Mod 支持仍不在已实现范围。功能和可靠性应根据实际操作、保存验证、原生测试和游戏回读结果判断。

可核对的原始字节数、文件摘要、分类汇总和大文件路径见 [build15-size-comparison.json](build15-size-comparison.json)。安装包版本与原生验证结果见 [BUILD15_VERIFICATION.md](BUILD15_VERIFICATION.md)。
