---
doc_name: "Multipass 构建与部署指南"
doc_type: "技术文档"
version: "v1.0"
generated_at: "2026-04-05 16:29:12"
project_root: "/Users/tompyang/Documents/code/multipass"
project_type: "general"
project_lang: "C++"
doc_status: "draft"
doc_depth: "standard"
analyzed_files:
  - "BUILD.linux.md"
  - "BUILD.macOS.md"
  - "BUILD.windows.md"
  - "CMakeLists.txt"
  - "CMakePresets.json"
  - "vcpkg.json"
  - "snap/snapcraft.yaml"
---

# Multipass 构建与部署指南

## 目录

- [构建前提条件](#构建前提条件)
- [Linux 构建](#linux-构建)
- [macOS 构建](#macos-构建)
- [Windows 构建](#windows-构建)
- [通用构建选项](#通用构建选项)
- [运行守护进程与客户端](#运行守护进程与客户端)
- [打包与发布](#打包与发布)
- [测试](#测试)
- [开发技巧](#开发技巧)
- [常见问题](#常见问题)

---

## 构建前提条件

### 通用要求

| 工具 | 版本要求 | 说明 |
|------|----------|------|
| CMake | >= 3.9 | 构建系统 |
| Git | 任意 | 版本控制 |
| Qt | 6.9.x | UI 框架（网络、事件循环等） |
| gRPC | 最新稳定版 | RPC 框架（通过 vcpkg 管理） |
| Protocol Buffers | 最新稳定版 | 序列化（通过 vcpkg 管理） |
| libssh | 最新稳定版 | SSH 支持（通过 vcpkg 管理） |
| OpenSSL | v3 | TLS 支持 |

> **Qt 版本说明**：Multipass 使用 Qt 6.9.1 测试。同一 6.9 轨道的更新补丁版本（如 6.9.2）应该兼容，更高次要版本可能存在兼容性问题。

### 依赖管理

- **Linux**：使用系统包管理器（apt）
- **macOS/Windows**：使用 **vcpkg** 管理 C++ 依赖

---

## Linux 构建

### 1. 安装构建依赖

```bash
cd <multipass>
sudo apt install devscripts equivs
mk-build-deps -s sudo -i
```

### 2. 初始化子模块

```bash
cd <multipass>
git submodule update --init --recursive
```

> **ARM/s390x/ppc64le/riscv 架构**：需要额外设置环境变量：
> ```bash
> export VCPKG_FORCE_SYSTEM_BINARIES=1
> ```

### 3. 配置构建

```bash
mkdir build
cd build
cmake ../
```

可选 CMake 参数：

| 参数 | 说明 | 示例 |
|------|------|------|
| `-DCMAKE_BUILD_TYPE` | 构建类型 | `Debug`、`Release`、`Coverage` |
| `-DMULTIPASS_VCPKG_LOCATION` | 自定义 vcpkg 路径 | `/path/to/vcpkg` |

### 4. 编译

```bash
cmake --build . --parallel
```

### 5. 安装运行时依赖

**AMD64 架构：**
```bash
sudo apt update
sudo apt install libgl1 libpng16-16 libxml2 dnsmasq-base \
    dnsmasq-utils qemu-utils libslang2 iproute2 iptables \
    iputils-ping libatm1 libxtables12 xterm
sudo apt install qemu-system-x86
```

**ARM64 架构：**
```bash
sudo apt update
sudo apt install libgl1 libpng16-16 libxml2 dnsmasq-base \
    dnsmasq-utils qemu-efi-aarch64 qemu-utils libslang2 \
    iproute2 iptables iputils-ping libatm1 libxtables12 xterm
sudo apt install qemu-system-aarch64
# 额外步骤
sudo cp /usr/share/qemu-efi-aarch64/QEMU_EFI.fd /usr/share/qemu/QEMU_EFI.fd
```

---

## macOS 构建

### 1. 安装 Xcode

通过 App Store 安装 Xcode，然后安装命令行工具：

```bash
xcode-select --install
# 配置 Xcode 开发者目录
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### 2. 安装 Homebrew

参考 [https://brew.sh/](https://brew.sh/) 安装 Homebrew。

### 3. 安装构建依赖

```bash
# 基础工具
brew install cmake ninja pkg-config

# QEMU（测试需要）
brew install qemu

# 额外库
brew install glib pixman

# 打包工具（可选）
brew install dylibbundler
```

### 4. 安装 CocoaPods（GUI 构建需要）

```bash
sudo gem install cocoapods
```

> **注意**：CocoaPods 可能需要 Ruby 3.1+，可使用 RVM 管理 Ruby 版本。
> 同时注意 OpenSSL 版本：RVM/Ruby 可能需要 OpenSSL v1，而 Multipass 构建需要 OpenSSL v3。

### 5. 初始化子模块并构建

```bash
cd <multipass>
git submodule update --init --recursive
mkdir build
cd build
cmake -GNinja ../
cmake --build . --parallel
```

### 6. 创建安装包

```bash
cmake --build . --target package
```

生成 `Multipass.pkg` 安装包。

---

## Windows 构建

### 1. 安装 Chocolatey

参考 [https://chocolatey.org/](https://chocolatey.org/) 安装 Chocolatey（需要管理员权限）。

### 2. 安装依赖（管理员 PowerShell）

```powershell
# 基础工具
choco install cmake ninja qemu-img git wget unzip -yfd

# Visual Studio 2022 构建工具
choco install visualstudio2022buildtools visualstudio2022-workload-vctools -yfd
```

> **Visual Studio 配置**：安装后，在 Visual Studio Installer 中确保选中 "C++/CLI support for v143 build tools"，并确保 vcpkg 未被选中。

### 3. 配置 Git 符号链接

参考 [git-for-windows 文档](https://github.com/git-for-windows/git/wiki/Symbolic-Links) 启用符号链接支持。

Windows 11 需要在"开发者设置"中启用"开发者模式"。

### 4. 配置 PATH

将 CMake 添加到 PATH：`C:\Program Files\CMake\bin`

### 5. 初始化子模块并构建

在 VS2022 开发者命令提示符中：

```batch
cd <multipass>
git submodule update --init --recursive
mkdir build
cd build
cmake -GNinja ..
cmake --build . --parallel
```

### 6. 启用 Hyper-V

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName:Microsoft-Hyper-V -All
```

---

## 通用构建选项

### CMake 构建类型

| 类型 | 说明 |
|------|------|
| `Debug` | 调试构建，包含调试符号，无优化 |
| `Release` | 发布构建，最大优化 |
| `RelWithDebInfo` | 发布构建，包含调试信息 |
| `Coverage` | 代码覆盖率构建 |

### 链接器选择（CMake >= 3.29）

构建系统会自动尝试使用 `mold` 或 `lld` 加速链接。可通过 `CMAKE_LINKER_TYPE` 覆盖：

```bash
cmake -DCMAKE_LINKER_TYPE=DEFAULT ../
```

### 功能标志

项目支持通过 `feature-flags.cmake` 控制功能开关：

```bash
cmake -DMULTIPASS_ENABLE_FEATURE_X=ON ../
```

---

## 运行守护进程与客户端

### Linux

```bash
# 启动守护进程（需要 root 权限）
sudo <multipass>/build/bin/multipassd &

# 配置 GUI 自动启动文件
mkdir -p ~/.local/share/multipass/
cp <multipass>/src/client/gui/assets/multipass.gui.autostart.desktop ~/.local/share/multipass/

# 启用 Bash 自动补全（可选）
source <multipass>/completions/bash/multipass

# 添加到 PATH
export PATH=<multipass>/build/bin:$PATH

# 使用 CLI
multipass launch --name foo

# 启动 GUI
multipass.gui
```

### macOS

```bash
# 启动守护进程
sudo <multipass>/build/bin/multipassd &

# 使用 CLI
<multipass>/build/bin/multipass launch

# 查看守护进程日志（已安装版本）
sudo launchctl debug system/com.canonical.multipassd --stdout --stderr
sudo launchctl kickstart -k system/com.canonical.multipassd
```

### Windows

```powershell
# 启动守护进程（管理员 PowerShell）
multipassd --logger=stderr

# 或安装为 Windows 服务
multipassd /install

# 卸载服务
multipassd /uninstall

# 扩展 PATH（当前会话）
$env:Path += ";<multipass>\build\bin"
$env:Path += ";<multipass>\build\bin\windows\x64\runner\Release"

# 使用 CLI
multipass help

# 启动 GUI
multipass.gui
```

---

## 打包与发布

### Linux（Snap）

Multipass 在 Linux 上以 Snap 包形式发布：

```bash
# 安装 snapcraft
sudo snap install snapcraft --classic

# 构建 Snap 包
cd <multipass>
snapcraft

# 安装本地构建的 Snap
sudo snap install multipass_*.snap --dangerous
```

Snap 配置文件：`snap/snapcraft.yaml`

### macOS（PKG 安装包）

```bash
cd build
cmake --build . --target package
# 生成 Multipass.pkg
```

### Windows（安装程序）

```batch
cd build
cmake --build . --target package
# 生成 Windows 安装程序
```

---

## 测试

### 单元测试

```bash
cd build
# 运行所有测试
ctest --parallel

# 运行特定测试
./bin/multipass_tests --gtest_filter="TestName*"
```

### CLI 集成测试

CLI 测试位于 `tests/cli/` 目录，通过 GitHub Actions 在真实环境中运行。

### 代码覆盖率

```bash
mkdir build-coverage
cd build-coverage
cmake -DCMAKE_BUILD_TYPE=Coverage ../
cmake --build . --parallel
ctest
# 生成覆盖率报告
```

---

## 开发技巧

### 获取版本信息

如果从 fork 仓库构建（使用"仅复制主分支"选项），需要手动获取标签：

```bash
git fetch --tags https://github.com/canonical/multipass.git
```

### 代码格式化

项目使用 `clang-format` 进行代码格式化：

```bash
# 格式化单个文件
clang-format -i src/daemon/daemon.cpp

# 检查格式（不修改）
clang-format --dry-run src/daemon/daemon.cpp
```

格式配置文件：`.clang-format`

### 代码静态分析

项目使用 `clang-tidy` 进行静态分析：

```bash
# 在构建目录中运行
clang-tidy -p build src/daemon/daemon.cpp
```

配置文件：`.clang-tidy`

### Git Hooks

项目提供 Git commit-msg 钩子，用于验证提交信息格式：

```bash
# 安装 Git hooks
cp git-hooks/commit-msg.py .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg

# 安装 Python 依赖
pip install -r git-hooks/requirements.txt
```

---

## 常见问题

### Linux

**Q: 构建时找不到 Qt**

```bash
# 确保 Qt 已安装并设置 CMAKE_PREFIX_PATH
cmake -DCMAKE_PREFIX_PATH=/path/to/qt6 ../
```

**Q: QEMU 无法启动虚拟机**

```bash
# 检查 KVM 是否可用
ls /dev/kvm
# 将用户添加到 kvm 组
sudo usermod -aG kvm $USER
```

### macOS

**Q: OpenSSL 版本冲突**

```bash
# 切换到 OpenSSL v3
brew link --force openssl@3
```

**Q: Python 缺少 tomli**

```bash
pip3 install tomli
```

**Q: 缺少 distlib**

```bash
python3 -m venv ~/multipass-build-env
source ~/multipass-build-env/bin/activate
pip install distlib
# 然后在 cmake 中指定
cmake -DPYTHON_EXECUTABLE=$VIRTUAL_ENV/bin/python3 ../
```

### Windows

**Q: CMake 找不到 MSVC 编译器**

确保在 VS2022 开发者命令提示符中运行 CMake，或使用 PowerShell 导入 VS 开发环境：

```powershell
$VSPath = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -products Microsoft.VisualStudio.Product.BuildTools -latest -property installationPath
Import-Module "$VSPath\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
Enter-VsDevShell -VsInstallPath "$VSPath" -DevCmdArguments '-arch=x64'
```

**Q: multipassd 需要管理员权限**

`multipassd` 需要管理员权限来创建符号链接和管理 Hyper-V 实例。如果不需要符号链接支持，可以将用户添加到 Hyper-V Administrators 组后以普通权限运行。

---

*文档生成时间：2026-04-05 | 版本：v1.0*
