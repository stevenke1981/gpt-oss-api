"""
GPT-OSS 20B Frontend (Gradio)
Connects to llama-server via /v1/chat/completions (OpenAI-compatible)

Usage:
    pip install -r requirements.txt
    python app.py
    python app.py --host 0.0.0.0 --port 7860  # LAN access
"""

import argparse
import json
import httpx
import gradio as gr
from openai import OpenAI

# ─── CLI args ────────────────────────────────────────────────
parser = argparse.ArgumentParser()
parser.add_argument("--server", default="http://127.0.0.1:8080", help="llama-server URL")
parser.add_argument("--host",   default="127.0.0.1")
parser.add_argument("--port",   default=7860, type=int)
parser.add_argument("--share",  action="store_true", help="Gradio public link")
args, _ = parser.parse_known_args()

LLAMA_URL = args.server

client = OpenAI(base_url=f"{LLAMA_URL}/v1", api_key="not-needed")

# ─── built-in tools (no API key needed) ─────────────────────
TOOLS_SCHEMA = [
    {
        "type": "function",
        "function": {
            "name": "web_search",
            "description": "Search the web via DuckDuckGo for real-time information",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"}
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "web_open",
            "description": "Fetch and read the content of a web page",
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "Full URL to fetch"}
                },
                "required": ["url"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get current weather for a city",
            "parameters": {
                "type": "object",
                "properties": {
                    "city": {"type": "string"},
                    "unit": {"type": "string", "enum": ["celsius", "fahrenheit"], "default": "celsius"},
                },
                "required": ["city"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "calculate",
            "description": "Evaluate a math expression",
            "parameters": {
                "type": "object",
                "properties": {
                    "expression": {"type": "string", "description": "e.g. 1234 * 5678"}
                },
                "required": ["expression"],
            },
        },
    },
]


# ─── tool execution ──────────────────────────────────────────
def execute_tool(name: str, args_str: str) -> str:
    try:
        args = json.loads(args_str)
    except Exception:
        return f"Error: invalid arguments JSON: {args_str}"

    if name == "web_search":
        query = args.get("query", "")
        try:
            resp = httpx.get(
                "https://api.duckduckgo.com/",
                params={"q": query, "format": "json", "no_redirect": "1", "no_html": "1"},
                timeout=8,
            )
            data = resp.json()
            results = []
            if data.get("AbstractText"):
                results.append(f"**{data['AbstractText']}**")
                results.append(f"Source: {data.get('AbstractURL','')}")
            for t in data.get("RelatedTopics", [])[:5]:
                if isinstance(t, dict) and t.get("Text"):
                    results.append(f"- {t['Text']}")
            return "\n".join(results) if results else f"No results for: {query}"
        except Exception as e:
            return f"Search error: {e}"

    if name == "web_open":
        url = args.get("url", "")
        try:
            from bs4 import BeautifulSoup
            resp = httpx.get(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=12, follow_redirects=True)
            soup = BeautifulSoup(resp.text, "html.parser")
            for tag in soup(["script", "style", "nav", "footer", "header"]):
                tag.decompose()
            lines = [l for l in soup.get_text("\n", strip=True).splitlines() if l.strip()]
            return "\n".join(lines[:200])
        except Exception as e:
            return f"Fetch error: {e}"

    if name == "get_weather":
        city = args.get("city", "")
        unit = args.get("unit", "celsius")
        try:
            resp = httpx.get(f"https://wttr.in/{city}?format=j1", timeout=8)
            c = resp.json()["current_condition"][0]
            temp = c["temp_C"] if unit == "celsius" else c["temp_F"]
            sym = "°C" if unit == "celsius" else "°F"
            return json.dumps({
                "city": city, "temp": f"{temp}{sym}",
                "condition": c["weatherDesc"][0]["value"],
                "humidity": f"{c['humidity']}%",
                "wind": f"{c['windspeedKmph']} km/h",
            }, ensure_ascii=False)
        except Exception as e:
            return f"Weather error: {e}"

    if name == "calculate":
        expr = args.get("expression", "")
        allowed = set("0123456789+-*/()., %")
        if not all(c in allowed for c in expr):
            return "Error: only basic operators allowed"
        try:
            return str(eval(expr, {"__builtins__": {}}))  # noqa: S307
        except Exception as e:
            return f"Calc error: {e}"

    return f"Unknown tool: {name}"


# ─── server health check ─────────────────────────────────────
def get_server_info() -> str:
    try:
        h = httpx.get(f"{LLAMA_URL}/health", timeout=3).json()
        status = h.get("status", "?")
        idle   = h.get("slots_idle", "?")
        busy   = h.get("slots_processing", "?")
        return f"🟢 {status}  |  slots: {idle} idle / {busy} busy"
    except Exception:
        return f"🔴 Offline — {LLAMA_URL}"


# ─── core chat function (streaming + tool loop) ──────────────
def chat(
    message: str,
    history: list,
    system_prompt: str,
    temperature: float,
    max_tokens: int,
    top_p: float,
    repeat_penalty: float,
    enable_tools: bool,
    tool_choice: str,
):
    if not message.strip():
        yield history, ""
        return

    # build messages
    messages = []
    if system_prompt.strip():
        messages.append({"role": "system", "content": system_prompt.strip()})
    for user_msg, assistant_msg in history:
        if user_msg:
            messages.append({"role": "user", "content": user_msg})
        if assistant_msg:
            messages.append({"role": "assistant", "content": assistant_msg})
    messages.append({"role": "user", "content": message})

    history = history + [[message, ""]]

    kwargs = dict(
        model="gpt-oss-20b",
        messages=messages,
        temperature=temperature,
        max_tokens=max_tokens,
        top_p=top_p,
        frequency_penalty=repeat_penalty - 1.0,   # map repeat_penalty to frequency_penalty
        stream=True,
    )
    if enable_tools:
        kwargs["tools"] = TOOLS_SCHEMA
        kwargs["tool_choice"] = tool_choice

    full_reply = ""
    pending_tool_calls: dict[str, dict] = {}

    try:
        with client.chat.completions.stream(**kwargs) as stream:
            for chunk in stream:
                delta = chunk.choices[0].delta if chunk.choices else None
                if delta is None:
                    continue

                # ── text delta ───────────────────────────
                if delta.content:
                    full_reply += delta.content
                    history[-1][1] = full_reply
                    yield history, ""

                # ── tool call delta ──────────────────────
                if delta.tool_calls:
                    for tc in delta.tool_calls:
                        idx = tc.index
                        if idx not in pending_tool_calls:
                            pending_tool_calls[idx] = {"id": "", "name": "", "args": ""}
                        if tc.id:
                            pending_tool_calls[idx]["id"] = tc.id
                        if tc.function.name:
                            pending_tool_calls[idx]["name"] += tc.function.name
                        if tc.function.arguments:
                            pending_tool_calls[idx]["args"] += tc.function.arguments

                finish = chunk.choices[0].finish_reason if chunk.choices else None
                if finish == "tool_calls" and pending_tool_calls:
                    # show tool call badge
                    for tc in pending_tool_calls.values():
                        full_reply += f"\n\n🔧 **{tc['name']}**`({tc['args']})`\n"
                    history[-1][1] = full_reply
                    yield history, ""

                    # execute tools
                    messages.append({
                        "role": "assistant",
                        "content": None,
                        "tool_calls": [
                            {"id": tc["id"], "type": "function",
                             "function": {"name": tc["name"], "arguments": tc["args"]}}
                            for tc in pending_tool_calls.values()
                        ],
                    })
                    for tc in pending_tool_calls.values():
                        result = execute_tool(tc["name"], tc["args"])
                        full_reply += f"\n📋 **Result:** {result[:300]}\n"
                        history[-1][1] = full_reply
                        yield history, ""
                        messages.append({
                            "role": "tool",
                            "tool_call_id": tc["id"],
                            "content": result,
                        })

                    # second pass (model reads tool results)
                    pending_tool_calls.clear()
                    full_reply += "\n\n"
                    kwargs2 = {**kwargs, "messages": messages, "stream": True}
                    kwargs2.pop("tools", None); kwargs2.pop("tool_choice", None)

                    with client.chat.completions.stream(**kwargs2) as stream2:
                        for chunk2 in stream2:
                            d2 = chunk2.choices[0].delta if chunk2.choices else None
                            if d2 and d2.content:
                                full_reply += d2.content
                                history[-1][1] = full_reply
                                yield history, ""
                    break

    except Exception as e:
        history[-1][1] = f"❌ Error: {e}"
        yield history, ""
        return

    yield history, ""


# ─── export chat ─────────────────────────────────────────────
def export_chat(history: list) -> str:
    lines = []
    for user_msg, assistant_msg in history:
        if user_msg:
            lines.append(f"**User:** {user_msg}\n")
        if assistant_msg:
            lines.append(f"**Assistant:** {assistant_msg}\n")
        lines.append("---\n")
    return "\n".join(lines)


# ─── Gradio UI ───────────────────────────────────────────────
SYSTEM_DEFAULT = (
    "You are a helpful assistant. Be concise and accurate. "
    "When you have access to tools, use them to get real-time information."
)

css = """
.chatbot-container { height: 520px !important; }
.tool-badge { background: #1e3a5f; border-radius: 6px; padding: 4px 8px; }
footer { display: none !important; }
"""

with gr.Blocks(title="GPT-OSS 20B", css=css, theme=gr.themes.Soft()) as demo:

    gr.Markdown("## 🤖 GPT-OSS 20B Chat")
    status_bar = gr.Markdown(get_server_info())

    with gr.Row():
        # ── left: chat ──────────────────────────────────────
        with gr.Column(scale=3):
            chatbot = gr.Chatbot(
                label="",
                height=520,
                show_copy_button=True,
                avatar_images=("🧑", "🤖"),
                render_markdown=True,
                elem_classes="chatbot-container",
            )
            with gr.Row():
                msg_box = gr.Textbox(
                    placeholder="Type a message...  (Shift+Enter = new line, Enter = send)",
                    lines=2,
                    scale=5,
                    show_label=False,
                    autofocus=True,
                )
                send_btn = gr.Button("Send ▶", variant="primary", scale=1, min_width=80)

            with gr.Row():
                clear_btn  = gr.Button("🗑 Clear", scale=1)
                export_btn = gr.Button("💾 Export", scale=1)
                refresh_btn = gr.Button("🔄 Status", scale=1)

            export_out = gr.Textbox(label="Export (copy this)", visible=False, lines=8)

        # ── right: settings ─────────────────────────────────
        with gr.Column(scale=1, min_width=260):
            gr.Markdown("### ⚙️ Settings")

            system_prompt = gr.Textbox(
                label="System Prompt",
                value=SYSTEM_DEFAULT,
                lines=4,
            )

            with gr.Accordion("Sampling", open=True):
                temperature = gr.Slider(0.0, 2.0, value=0.8, step=0.05, label="Temperature")
                max_tokens  = gr.Slider(64, 4096, value=512, step=64,  label="Max Tokens")
                top_p       = gr.Slider(0.0, 1.0, value=0.95, step=0.05, label="Top-P")
                rep_penalty = gr.Slider(1.0, 1.5, value=1.1, step=0.01, label="Repeat Penalty")

            with gr.Accordion("Tools", open=True):
                enable_tools = gr.Checkbox(label="Enable built-in tools", value=False)
                tool_choice  = gr.Radio(
                    ["auto", "none", "required"],
                    value="auto",
                    label="Tool choice",
                )
                gr.Markdown(
                    "**Available tools:**  \n"
                    "`web_search` `web_open` `get_weather` `calculate`",
                )

            with gr.Accordion("Custom Function", open=False):
                gr.Markdown("_Paste your tool JSON definition below and enable tools above._")
                custom_fn_json = gr.Code(
                    language="json",
                    label="Tool JSON",
                    value=json.dumps({
                        "type": "function",
                        "function": {
                            "name": "my_tool",
                            "description": "Describe what this tool does",
                            "parameters": {
                                "type": "object",
                                "properties": {
                                    "param1": {"type": "string", "description": "..."}
                                },
                                "required": ["param1"]
                            }
                        }
                    }, indent=2),
                )

    # ── event wiring ─────────────────────────────────────────
    inputs = [msg_box, chatbot, system_prompt,
              temperature, max_tokens, top_p, rep_penalty,
              enable_tools, tool_choice]

    msg_box.submit(chat,  inputs=inputs, outputs=[chatbot, msg_box])
    send_btn.click(chat,  inputs=inputs, outputs=[chatbot, msg_box])
    clear_btn.click(lambda: ([], ""), outputs=[chatbot, msg_box])
    refresh_btn.click(get_server_info, outputs=status_bar)

    def do_export(history):
        text = export_chat(history)
        return gr.update(visible=True, value=text)

    export_btn.click(do_export, inputs=chatbot, outputs=export_out)


if __name__ == "__main__":
    demo.launch(
        server_name=args.host,
        server_port=args.port,
        share=args.share,
        show_error=True,
    )
