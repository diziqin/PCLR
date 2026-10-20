# Plain Craft Launcher (PCL) PCLR

**PCLR 是第三方独立修改版，由 diziqin 维护，基于龙腾猫跃的 [Plain Craft Launcher](https://github.com/Meloong-Git/PCL) 公开源码制作。**

上游作者：**龙腾猫跃** · [支持原作者](https://meloong.com/afd/a/LTCat) · [上游原始说明](README.upstream.md)

[下载 PCLR](https://github.com/diziqin/PCLR/releases/latest) · [全部发行与上游历史归档](https://github.com/diziqin/PCLR/releases) · [提交问题](https://github.com/diziqin/PCLR/issues)

## 当前版本

PCLR **2.99.0.2** 基于上游 **2.99.0.0**（`6b9a50df911c9d68b69b24c979efba477fb14b67`）。

- 恢复 Minecraft 本体下载、自动安装及整合包安装入口。
- 使用 PCLR 名称和独立的注册表、应用数据、单实例标识；保留蓝色界面、原作者署名与赞助入口。
- 保留上游正版购买劝导、赞助劝导及第三方组件声明。
- “检查更新”打开本仓库的最新发行页面；不从上游自动覆盖安装。
- 修复 CurseForge 不可用：沿用上游数据结构与下载流程，未配置专用 API Key 时使用 `https://api.curse.tools` 公开兼容接口；已配置 Key 时优先官方接口。原有 MCIM 接口已暂停服务。

修改仅恢复客户端入口，未对 Mojang、BMCLAPI、CurseForge 或 Modrinth 服务作任何修改；实际下载仍受下载源及网络状态影响。

## 使用

需要 **64 位 Windows 与 .NET Framework 4.8**。

从最新发行页下载 `PCLR-2.99.0.2-windows-Release.zip`，解压到独立目录并运行 `PCLR.exe`。也可以下载同名的独立 `.exe`。`Debug` 与 `Snapshot` 为排错和预览构建，普通使用请选择 `Release`。

请在新目录中使用，避免与原版共用目录内的 `PCL/Setup.ini`。游戏文件可以通过添加现有 Minecraft 文件夹复用。

CurseForge 默认可通过公开兼容接口访问，无需使用者提供 API Key。该接口是第三方公益服务，可能受缓存和可用性影响；本项目不会向该接口转发使用者的官方 API Key。

公开源码不包含上游的微软应用配置与 CurseForge 密钥。如需微软登录或 CurseForge 官方直连，可在运行 PCLR 前提供自己的配置：

```powershell
$env:PCL_MS_CLIENT_ID = '你自行申请的微软应用 Client ID'
$env:PCL_CURSEFORGE_API_KEY = '你自行申请的 CurseForge API Key'
.\PCLR.exe
```

这些配置仅用于对应的官方服务；Minecraft 下载、Modrinth 与 CurseForge 公共兼容接口均不依赖它们。请勿向仓库提交个人密钥。

## 构建与验证

使用 Visual Studio 2022 17.14 或更新的 MSBuild（安装 .NET 桌面开发工作负载与 .NET Framework 4.8 目标包）、.NET 9 SDK、PowerShell 7。

```powershell
git clone --recurse-submodules https://github.com/diziqin/PCLR.git
Set-Location PCLR
pwsh ./scripts/Build-Release.ps1 -Configuration Release
```

`Debug`、`Release`、`Snapshot` 使用同一份源码构建。GitHub Actions 执行三种构建、检查已编译的下载开关与产品信息，生成便携包、独立程序、包含 MeloongCore 子模块的源码包与 SHA-256 校验清单。推送 `v*` 标签时自动发布。

## 上游历史归档

历史发行使用上游原有标签并明确标记为“上游归档”；它们是上游原版，不包含 PCLR 的修复。归档保留发行说明与原始来源。

上游部分发行只有源码，没有公开对应的二进制包。仅归档能够从上游验证的真实文件，不将旧版程序标作新版。具体可用情况、原始提交、Git blob 与 SHA-256 见 [历史归档索引](docs/upstream-history.json)。GitHub 自动生成的源码归档不包含子模块内容，PCLR 自有版本另提供完整源码包。

共索引 88 条上游发行记录，验证 50 份原样压缩包。上游 2.6.15 原包及 2.6.10 的重新签名变体被本机 Windows 安全软件拦截，按维护者选择的处理原则不单独重新上传；保留源码记录与上游原包链接。2.6.10 另有通过文件校验的原始变体可供归档。此处不对被拦截历史文件的安全性作结论。

## 许可与鸣谢

保留并遵循上游的 [《PCL 分发有限许可》与《PCL 存储库合理使用指南》](LICENCE)。本项目不将上游代码重新许可为 MIT 或 Apache。`MeloongCore` 和其他组件分别遵循各自许可，见 [第三方声明](THIRD_PARTY_NOTICES.md)。

PCLR 与 PCL 官方、Mojang、Microsoft、网易不存在隶属或官方合作关系。有关本修改版的问题请提交到本仓库。
