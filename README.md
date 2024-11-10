
# ModelScope

ModelScope 是一个用于从 ModelScope.cn 下载模型的 Swift 包。

## 功能特点

- 支持从 ModelScope.cn 下载模型文件
- 支持进度跟踪
- 支持断点续传
- 文件完整性验证
- 自动创建目录结构

## 安装

### Swift Package Manager

将以下依赖添加到你的 `Package.swift` 文件中：

```swift
dependencies: [
    .package(url: "https://github.com/WtecHtec/ModelScope.git", from: "1.0.0")
]
```

## 使用方法

```swift
import ModelScope

// https://www.modelscope.cn/models/ZhipuAI/glm-4-voice-9b
 var downloadManager: ModelScope.DownloadManager = ModelScope.DownloadManager("ZhipuAI/glm-4-voice-9b")
// 开始下载模型
 Task {
     await downloadManager.downloadModel(
        downFolder: "保存路径",
        modelId: "模型ID",
        progress: { progress in
            print("下载进度: \(progress)")
        },
        completion: { result in
            switch result {
            case .success:
                print("下载完成")
            case .failure(let error):
                print("下载失败: \(error)")
            }
        }
    )
 }
```

