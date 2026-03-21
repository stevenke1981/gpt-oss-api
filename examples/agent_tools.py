"""
GPT-OSS 20B Tool Use via OpenAI Agents SDK
Official approach from github.com/openai/gpt-oss/examples/agents-sdk-python

Install:
    pip install openai-agents httpx beautifulsoup4

llama-server must be running:
    ./linux/serve.sh   or   .\windows\serve.ps1
"""

import asyncio
import httpx
import json
from bs4 import BeautifulSoup

from openai import AsyncOpenAI
from agents import (
    Agent,
    ItemHelpers,
    Runner,
    set_default_openai_api,
    set_default_openai_client,
    set_tracing_disabled,
    function_tool,
)

# ─── connect to llama-server ─────────────────────────────────
openai_client = AsyncOpenAI(
    api_key="not-needed",
    base_url="http://127.0.0.1:8080/v1",
)

set_tracing_disabled(True)
set_default_openai_client(openai_client)
set_default_openai_api("chat_completions")

MODEL = "gpt-oss-20b"   # llama-server ignores this, uses loaded model

# ─── tool: web search (DuckDuckGo instant answer) ────────────
@function_tool
async def web_search(query: str) -> str:
    """Search the web using DuckDuckGo and return top results."""
    url = "https://api.duckduckgo.com/"
    params = {"q": query, "format": "json", "no_redirect": "1", "no_html": "1"}
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(url, params=params)
        data = resp.json()

    results = []
    # Abstract answer
    if data.get("AbstractText"):
        results.append(f"Summary: {data['AbstractText']}")
        results.append(f"Source: {data.get('AbstractURL', '')}")

    # Related topics
    for topic in data.get("RelatedTopics", [])[:5]:
        if isinstance(topic, dict) and topic.get("Text"):
            results.append(f"- {topic['Text']}")
            if topic.get("FirstURL"):
                results.append(f"  URL: {topic['FirstURL']}")

    if not results:
        return f"No instant results for '{query}'. Try web_open with a specific URL."

    return "\n".join(results)


# ─── tool: open web page ─────────────────────────────────────
@function_tool
async def web_open(url: str) -> str:
    """Fetch a web page and return its readable text content."""
    headers = {"User-Agent": "Mozilla/5.0 (compatible; GPT-OSS-Agent/1.0)"}
    async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
        resp = await client.get(url, headers=headers)
        resp.raise_for_status()

    soup = BeautifulSoup(resp.text, "html.parser")

    # remove noise
    for tag in soup(["script", "style", "nav", "footer", "header", "aside"]):
        tag.decompose()

    text = soup.get_text(separator="\n", strip=True)
    # trim to context-safe size
    lines = [l for l in text.splitlines() if l.strip()]
    return "\n".join(lines[:200])   # ~4000 tokens


# ─── tool: get current weather ───────────────────────────────
@function_tool
async def get_weather(city: str, unit: str = "celsius") -> str:
    """Get current weather for a city using wttr.in (no API key needed)."""
    url = f"https://wttr.in/{city}?format=j1"
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(url)
        data = resp.json()

    current = data["current_condition"][0]
    temp_c  = current["temp_C"]
    temp_f  = current["temp_F"]
    desc    = current["weatherDesc"][0]["value"]
    humidity = current["humidity"]
    wind_kmph = current["windspeedKmph"]

    temp = temp_c if unit == "celsius" else temp_f
    unit_sym = "°C" if unit == "celsius" else "°F"

    return json.dumps({
        "city": city,
        "temperature": f"{temp}{unit_sym}",
        "condition": desc,
        "humidity": f"{humidity}%",
        "wind": f"{wind_kmph} km/h"
    }, ensure_ascii=False)


# ─── tool: calculator ────────────────────────────────────────
@function_tool
def calculate(expression: str) -> str:
    """Evaluate a mathematical expression safely."""
    allowed = set("0123456789+-*/()., %")
    if not all(c in allowed for c in expression):
        return "Error: only basic math operators allowed"
    try:
        result = eval(expression, {"__builtins__": {}})  # noqa: S307
        return str(result)
    except Exception as e:
        return f"Error: {e}"


# ─── create agent ────────────────────────────────────────────
agent = Agent(
    name="GPT-OSS Agent",
    instructions=(
        "You are a helpful assistant with access to web search, weather, "
        "and calculation tools. Use tools when you need real-time information. "
        "Always cite sources when presenting web search results."
    ),
    tools=[web_search, web_open, get_weather, calculate],
    model=MODEL,
)


# ─── streaming agent runner ──────────────────────────────────
async def run_agent(user_input: str):
    print(f"\nUser: {user_input}")
    print("-" * 50)

    result = Runner.run_streamed(agent, user_input)

    async for event in result.stream_events():
        if event.type == "raw_response_event":
            continue
        elif event.type == "run_item_stream_event":
            item = event.item
            if item.type == "tool_call_item":
                print(f"[Tool call] {item.raw_item.name}({item.raw_item.arguments})")
            elif item.type == "tool_call_output_item":
                preview = str(item.output)[:120].replace("\n", " ")
                print(f"[Tool result] {preview}...")
            elif item.type == "message_output_item":
                text = ItemHelpers.text_message_output(item)
                print(f"\nAssistant: {text}")

    print("=" * 50)


# ─── interactive REPL ────────────────────────────────────────
async def repl():
    print("GPT-OSS 20B Agent — type 'quit' to exit")
    print("Available tools: web_search, web_open, get_weather, calculate")
    print("=" * 50)

    while True:
        try:
            user_input = input("\n> ").strip()
        except (EOFError, KeyboardInterrupt):
            break

        if user_input.lower() in ("quit", "exit", "q"):
            break
        if not user_input:
            continue

        try:
            await run_agent(user_input)
        except Exception as e:
            print(f"[Error] {e}")


# ─── demo examples ───────────────────────────────────────────
async def demo():
    examples = [
        "What is the weather in Taipei right now?",
        "Search for the latest news about llama.cpp",
        "What is 1234 * 5678 + 99?",
        "Open https://tw.yahoo.com and summarize today's top news",
    ]
    for q in examples:
        await run_agent(q)


if __name__ == "__main__":
    import sys
    if "--demo" in sys.argv:
        asyncio.run(demo())
    else:
        asyncio.run(repl())
