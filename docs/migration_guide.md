# VaultStream 迁移到 Windows 方案

为了确保迁移过程高效且减少不必要的流量消耗，请按照以下步骤在 Linux 上打包，并在 Windows 上恢复。

## 第一步：在 Linux 上进行深度清理 (瘦身)

为了减小压缩包体积，我们需要删除所有自动生成的缓存和构建文件。

### 1. 清理前端

在 `frontend/` 目录下执行：

```bash
flutter clean
```

### 2. 清理后端环境

删除 Python 虚拟环境（Windows 需要重新生成）：

```bash
rm -rf backend/.venv
```

---

## 第二步：打包项目 (排除冗余文件)

建议在 **VaultStream 根目录** 运行以下命令，使用 `tar` 创建一个极致瘦身的压缩包，排除掉 `.git` 和大型缓存。

```bash
tar -czvf VaultStream_Migration.tar.gz \
    --exclude='frontend/build' \
    --exclude='frontend/.dart_tool' \
    --exclude='frontend/.pub-cache' \
    --exclude='backend/.venv' \
    --exclude='.venv' \
    --exclude='.git' \
    --exclude='backend/__pycache__' \
    .
```

_如果你更习惯用 ZIP，可以使用：_

```bash
zip -r VaultStream_Migration.zip . -x "frontend/build/*" "frontend/.dart_tool/*" "backend/.venv/*" ".git/*"
```

---

## 第三步：传输到 Windows

---

## 第四步：在 Windows 上恢复开发环境

1.  **解压**：将 `VaultStream_Migration.tar.gz` 解压到 D 盘或 E 盘（推荐有充足空间的分区）。
2.  **安装 Flutter**：[下载并配置 Flutter Windows SDK](https://docs.flutter.dev/get-started/install/windows)。
3.  **配置 Android Studio**：
    - 在 Android Studio 设置中配置好 **HTTP Proxy**。
    - **重要**：进入 `frontend/android/gradle.properties`，将 `systemProp.http.proxyHost=127.0.0.1` 修改为你的 Windows 代理配置（如果没变则保持原样）。
4.  **恢复前端依赖**：
    ```powershell
    cd frontend
    flutter pub get
    ```
5.  **恢复后端环境**：
    ```powershell
    cd backend
    python -m venv .venv
    .\.venv\Scripts\activate
    pip install -r requirements.txt
    ```

---

## 复用清单 (Checklist)

- [x] `backend/data/vaultstream.db` (数据库)
- [x] `backend/data/media/` (媒体文件)
- [x] `backend/.env` (配置文件)
- [x] `frontend/lib/` (Flutter 源码)
- [x] `.github/workflows/` (打包配置)
