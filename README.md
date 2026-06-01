# BT录像 - 蓝牙麦克风录像 App

使用蓝牙设备（AirPods/无线麦克风）收音的相机录像应用。

## 功能

- 📹 **高画质录像** - 支持 4K / 1080p / 720p，HEVC (H.265) 编码
- 🎧 **蓝牙收音** - 自动检测并切换到蓝牙麦克风
- 📷 **拍照** - 支持同时拍照
- 🔦 **闪光灯** - 手电筒模式
- 🔄 **前后切换** - 双击或按钮切换
- 🎯 **点击对焦** - 触摸屏幕对焦和曝光
- 🔍 **捏合缩放** - 手势缩放，最高 10x
- ☀️ **曝光补偿** - 长按显示曝光滑块
- 📊 **音频电平** - 实时显示麦克风输入电平
- 🎥 **视频稳定** - 电影级防抖

## 构建方式（Windows 无 Mac）

### 1. 准备 GitHub Secrets

在你的 GitHub 仓库 → Settings → Secrets and variables → Actions 中添加：

```
P12_BASE64       - cert.p12 的 base64 编码
P12_PASSWORD      - 证书密码（1）
PROVISION_PROFILE_BASE64 - cert.mobileprovision 的 base64 编码
KEYCHAIN_PASSWORD - 随便写一个临时密码（如 "temp123"）
```

### 2. 生成 Base64

在 PowerShell 中运行：

```powershell
# P12 证书
[Convert]::ToBase64String([IO.File]::ReadAllBytes("cert_temp\cert.p12")) | Set-Clipboard
# 粘贴到 P12_BASE64

# 描述文件
[Convert]::ToBase64String([IO.File]::ReadAllBytes("cert_temp\cert.mobileprovision")) | Set-Clipboard
# 粘贴到 PROVISION_PROFILE_BASE64
```

### 3. 推送代码

```bash
git init
git add .
git commit -m "initial"
git remote add origin https://github.com/你的用户名/bluetooth-mic.git
git push -u origin main
```

### 4. 下载 IPA

- 去 GitHub Actions 页面找到构建完成的 workflow
- 下载 `BluetoothMic-IPA` artifact
- 用 AltStore / Sideloadly / 爱思助手 安装到手机

## 技术细节

- AVCaptureSession + AVAudioSession 组合控制
- 音频路由通过 `setPreferredInput` 强制指定蓝牙设备
- 蓝牙走 HFP 协议，采样率 8-16kHz（硬件限制）
- 如果用 DJI Mic 等 USB-C 接收器设备，走的不是蓝牙 HFP，音质更好
