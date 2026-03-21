# GPT-OSS 20B 部署腳本

基於 [DavidAU/OpenAi-GPT-oss-20b-abliterated-uncensored-NEO-Imatrix-gguf](https://huggingface.co/DavidAU/OpenAi-GPT-oss-20b-abliterated-uncensored-NEO-Imatrix-gguf) 與 llama.cpp 的部署工具。

## 目錄結構

```
gpt-oss-api/
├── windows/
│   ├── download.bat   # 下載模型
│   ├── manage.bat     # 管理模型
│   └── serve.bat      # 啟動服務
├── linux/
│   ├── download.sh    # 下載模型
│   ├── manage.sh      # 管理模型
│   └── serve.sh       # 啟動服務
├── config/
│   └── settings.ini   # 統一設定檔 (host/port/GPU/採樣參數)
└── models/            # GGUF 模型存放目錄 (自動建立)
```

## 快速開始

### Windows (PowerShell)
```powershell
# 首次執行若遇到執行原則限制:
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

.\windows\download.ps1   # 選擇並下載模型
.\windows\manage.ps1     # 管理已下載模型
.\windows\serve.ps1      # 啟動 API 服務
```

### Linux / macOS
```bash
chmod +x linux/*.sh
./linux/download.sh    # 選擇並下載模型
./linux/manage.sh      # 管理已下載模型
./linux/serve.sh       # 啟動 API 服務
```

### 命令列快速模式
```bash
# Linux - 直接指定模型下載
./linux/download.sh OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf

# Linux - 直接指定模型路徑啟動服務
./linux/serve.sh ./models/OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf 8080

# Windows PowerShell 快速啟動
.\windows\serve.ps1 -Model ".\models\model.gguf" -Port 8080
```

## 模型選擇指南

| 量化 | 大小 | 用途 |
|------|------|------|
| IQ4_NL | ~12 GB | 創意/娛樂，Imatrix 效果最強 |
| Q5_1   | ~16 GB | 均衡一般用途，穩定性佳 |
| Q8_0   | ~22 GB | 最高品質 |

| Matrix 類型 | 說明 |
|------------|------|
| 標準 | 單資料集 Imatrix |
| DI-Matrix | 2 資料集平均，平衡特性 |
| TRI-Matrix | 3 資料集平均，最穩定 |

## 前置需求

### llama.cpp
- [GitHub Releases](https://github.com/ggerganov/llama.cpp/releases) 下載預編譯版
- 或自行編譯 (支援 CUDA / Metal / CPU)

### 下載工具 (擇一)
```bash
pip install huggingface_hub[cli]   # 推薦，支援 Token 認證
# 或 wget / curl (內建)
```

## API 使用範例

服務啟動後，相容 OpenAI API 格式：

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role": "user", "content": "Hello!"}],
    "temperature": 0.8,
    "max_tokens": 512
  }'
```

## 建議採樣參數

```
temperature:    0.8  (創意 1.0-1.2 / 程式碼 0.6)
repeat_penalty: 1.1  (重要! 防止輸出重複)
top_k:          40
top_p:          0.95
min_p:          0.05
```
