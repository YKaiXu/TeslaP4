# NVIDIA 驱动安装指南（Tesla P4）

> 适用环境：Ubuntu 26.04 LTS / Linux

## 1. 确认 GPU 硬件

首先确认系统识别到 Tesla P4：

```bash
lspci | grep -i nvidia
```

预期输出：
```
03:00.0 3D controller: NVIDIA Corporation GP104GL [Tesla P4] (rev a1)
```

## 2. 安装 NVIDIA 驱动

### 方法一：使用 Ubuntu 官方源（推荐）

```bash
# 查看可用的 NVIDIA 驱动版本
ubuntu-drivers devices

# 安装推荐版本的驱动
sudo apt update
sudo apt install -y nvidia-driver-580-server

# 重启
sudo reboot
```

### 方法二：从 NVIDIA 官网下载

```bash
# 下载驱动（以 580.159.03 为例）
wget https://us.download.nvidia.com/tesla/580.159.03/NVIDIA-Linux-x86_64-580.159.03.run
chmod +x NVIDIA-Linux-x86_64-580.159.03.run

# 安装
sudo ./NVIDIA-Linux-x86_64-580.159.03.run
sudo reboot
```

## 3. 验证驱动

```bash
nvidia-smi
```

预期输出：
```
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 580.159.03             Driver Version: 580.159.03     CUDA Version: 13.0 |
+-------------------------------+----------------------+----------------------+
| GPU  Name            Persistence-M | Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf     Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |
|====================================+======================+======================|
|   0  Tesla P4                  Off | 00000000:03:00.0 Off |                  0 |
| N/A   44C    P0             22W / 75W |   0MiB /   7680MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+
```

## 4. 安装 CUDA Toolkit（编译 llama.cpp 需要）

> 注意：仅运行 `nvidia-smi` 不需要此步骤。编译含 CUDA 后端的 llama.cpp 才需要。

### 方式一：通过 apt 安装（推荐）

```bash
sudo apt install -y nvidia-cuda-toolkit

# 验证
nvcc --version
```

### 方式二：安装特定版本

```bash
wget https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda_12.8.0_570.86.10_linux.run
sudo sh cuda_12.8.0_570.86.10_linux.run --toolkit --silent --override

echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
```

## 5. 常见驱动问题

| 问题 | 原因 | 解决 |
|------|------|------|
| `nvidia-smi` 提示未安装 | 驱动未正确安装 | `sudo apt install nvidia-utils-580-server` |
| `nvidia-smi` 显示 No devices | 显卡未被系统识别 | 检查 `lspci` 输出，确认 PCIe 插槽是否正常 |
| 内核模块不匹配 | 内核更新后驱动需要重装 | `sudo apt reinstall nvidia-driver-580-server && reboot` |
| CUDA 版本不匹配 | Toolkit 版本与驱动不匹配 | `nvidia-smi` 显示的 CUDA Version 是驱动支持的版本，实际用 `nvcc --version` 确认 |
| Xorg 占用了 GPU | 桌面环境使用了 P4 渲染 | 启动参数加 `--no-warmup` 或在 `/etc/X11/xorg.conf` 中禁用 P4 |
