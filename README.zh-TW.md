# GPT-OSS 20B 本地部署指南

基於 [llama.cpp](https://github.com/ggml-org/llama.cpp) 在本機執行 [OpenAI GPT-OSS 20B 解封版](https://huggingface.co/DavidAU/OpenAi-GPT-oss-20b-abliterated-uncensored-NEO-Imatrix-gguf)，提供 OpenAI 相容 API。

---

## 系統需求

| 項目 | 最低需求 |
|------|----------|
| RAM  | 16 GB（模型載入需要） |
| VRAM | 8 GB（GPU 加速）或無（純 CPU） |
| 磁碟 | 15–25 GB 可用空間（依量化版本） |
| OS   | Windows 10+ 或 Linux（Ubuntu 20.04+） |

---

## 一、安裝 llama.cpp

### Windows

執行安裝腳本，自動從 GitHub Releases 下載預編譯版本：

```powershell
# 若首次遇到執行原則限制，先執行一次：
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

cd gpt-oss-api
.\windows\install_llama.ps1
```

腳本會自動偵測顯示卡（NVIDIA / AMD / Intel / CPU）並下載對應版本。

**手動選擇版本：**

| 選項 | 適用情境 |
|------|----------|
| `cpu`    | 無顯示卡或相容性問題 |
| `vulkan` | 大多數現代顯示卡（通用） |
| `cuda12` | NVIDIA（驅動版本 527+） |
| `cuda13` | NVIDIA（驅動版本 576+） |
| `hip`    | AMD ROCm |
| `sycl`   | Intel Arc |

---

### Linux

執行編譯安裝腳本：

```bash
cd gpt-oss-api
chmod +x linux/*.sh
./linux/install_llama.sh
```

腳本會自動：
- 安裝缺少的套件（`cmake`、`g++`、`make`）
- 偵測 GPU 並選擇對應後端
- 編譯並安裝至 `~/.local/bin/llama-server`

安裝完成後讓 PATH 生效：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 二、下載模型

### Windows

```powershell
.\windows\download.ps1
```

### Linux

```bash
./linux/download.sh
```

依提示選擇量化版本：

| 量化 | 大小 | 建議用途 |
|------|------|----------|
| **IQ4_NL** | ~12 GB | 創意寫作、娛樂內容（Imatrix 效果最強） |
| **Q5_1**   | ~16 GB | 一般用途、均衡品質 |
| **Q8_0**   | ~22 GB | 最高品質（需要較大 VRAM） |

**Matrix 類型說明：**

| 類型 | 說明 |
|------|------|
| 標準 | 單一資料集 Imatrix |
| DI-Matrix | 2 個資料集平均，特性更平衡 |
| TRI-Matrix | 3 個資料集平均，輸出最穩定 |

> **提示：** 若需要認證（私有模型），先設定環境變數：
> ```bash
> export HF_TOKEN=hf_xxxxxxxxxxxxxxxx
> ```

---

## 三、啟動 API 服務

### Windows

```powershell
.\windows\serve.ps1

# 或直接指定參數（不需互動）：
.\windows\serve.ps1 -Model ".\models\OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf" -Port 8080
```

### Linux

```bash
./linux/serve.sh

# 或直接指定參數：
./linux/serve.sh ./models/OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf 8080
```

服務啟動後可使用的端點：

| 端點 | 說明 |
|------|------|
| `http://127.0.0.1:8080/v1/chat/completions` | 聊天補全（OpenAI 相容） |
| `http://127.0.0.1:8080/v1/completions`      | 文字補全 |
| `http://127.0.0.1:8080/health`              | 健康狀態 |
| `http://127.0.0.1:8080/metrics`             | 效能指標 |
| `http://127.0.0.1:8080`                     | Web UI（瀏覽器直接使用） |

---

## 四、API 使用範例

### curl

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role": "user", "content": "你好，請介紹你自己。"}],
    "temperature": 0.8,
    "max_tokens": 512
  }'
```

### Python

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8080/v1",
    api_key="not-needed"
)

response = client.chat.completions.create(
    model="gpt-oss-20b",
    messages=[{"role": "user", "content": "你好！"}],
    temperature=0.8,
    max_tokens=512
)
print(response.choices[0].message.content)
```

---

## 五、模型管理

### Windows

```powershell
.\windows\manage.ps1
```

### Linux

```bash
./linux/manage.sh
```

功能選單：
- 列出已下載模型（含大小、修改時間）
- 查看模型詳細資訊（量化類型、建議參數、SHA256）
- 刪除模型
- 磁碟空間資訊
- 清理不完整的下載檔案

---

## 六、設定調整

編輯 `config/settings.ini` 可修改預設值，無需每次重新輸入：

```ini
[server]
HOST=127.0.0.1
PORT=8080
N_GPU_LAYERS=0        # 0=純CPU, -1=全部層放GPU, 數字=指定層數

[inference]
CTX_SIZE=8192         # 上下文長度，最大 131072
N_PARALLEL=4          # 同時處理的請求數
N_THREADS=8           # CPU 執行緒數

[sampling]
TEMPERATURE=0.8
REPEAT_PENALTY=1.1    # 重要！防止輸出重複
TOP_K=40
TOP_P=0.95
MIN_P=0.05
```

---

## 七、採樣參數建議

| 用途 | Temperature | 說明 |
|------|-------------|------|
| 一般對話 | 0.7 – 0.9 | 平衡創意與連貫性 |
| 創意寫作 | 1.0 – 1.2 | 更豐富多變的輸出 |
| 程式碼   | 0.4 – 0.6 | 更精確、確定性高 |

> `repeat_penalty: 1.1` 是關鍵參數，請勿移除，否則模型容易陷入重複迴圈。

---

## 八、開放區網存取

預設服務只綁定 `127.0.0.1`（僅本機），執行防火牆腳本可一鍵開放區網：

### Windows（需要系統管理員）

```powershell
.\windows\firewall.ps1
```

腳本會自動：
1. 在 Windows 防火牆新增輸入規則（TCP 8080）
2. 將 `config/settings.ini` 的 `HOST` 改為 `0.0.0.0`

### Linux

```bash
./linux/firewall.sh
```

自動偵測並設定 `ufw` / `firewalld` / `iptables`，同時更新 config。

設定完成後重新啟動服務，區網裝置即可透過以下位址連線：

```
http://<你的IP>:8080/v1/chat/completions
http://<你的IP>:8080   ← Web UI
```

> **安全提醒：** `0.0.0.0` 會讓服務對區網所有裝置開放，請確認網路環境安全。若需要還原：
> - Windows：`Remove-NetFirewallRule -DisplayName "llama-server LAN"`
> - Linux (ufw)：`sudo ufw delete allow 8080/tcp`

---

## 十、常見問題

**Q: 服務啟動後立即退出？**
- VRAM 不足：降低 `N_GPU_LAYERS` 或 `CTX_SIZE`
- 模型檔案損壞：重新執行 download 腳本
- 埠號衝突：修改 `config/settings.ini` 的 `PORT`

**Q: 速度很慢？**
- 確認 `N_GPU_LAYERS=-1`（全部層放 GPU）
- 若 VRAM 不足以放全部層，設為適當的數字（例如 `20`）
- RTX 3060（12GB）可放全部 20B 模型的 IQ4_NL 量化版

**Q: 輸出品質不佳或一直重複？**
- 確認 `REPEAT_PENALTY=1.1`
- 嘗試降低 Temperature 至 0.6–0.8
- 換用 Q5_1 或 Q8_0 量化版本

**Q: Linux 找不到 llama-server？**
```bash
export PATH="$HOME/.local/bin:$PATH"
which llama-server
```

**Q: Windows 出現執行原則錯誤？**
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

---

## 目錄結構

```
gpt-oss-api/
├── config/
│   └── settings.ini          # 全域設定檔
├── windows/
│   ├── install_llama.ps1     # 安裝 llama.cpp（預編譯版）
│   ├── download.ps1          # 下載 GGUF 模型
│   ├── manage.ps1            # 模型管理
│   └── serve.ps1             # 啟動 API 服務
├── linux/
│   ├── install_llama.sh      # 編譯安裝 llama.cpp
│   ├── download.sh           # 下載 GGUF 模型
│   ├── manage.sh             # 模型管理
│   └── serve.sh              # 啟動 API 服務
└── models/                   # GGUF 模型存放目錄（自動建立）
```

---

## 相關連結

- [模型頁面（HuggingFace）](https://huggingface.co/DavidAU/OpenAi-GPT-oss-20b-abliterated-uncensored-NEO-Imatrix-gguf)
- [llama.cpp GitHub](https://github.com/ggml-org/llama.cpp)
- [llama.cpp Releases](https://github.com/ggml-org/llama.cpp/releases)
