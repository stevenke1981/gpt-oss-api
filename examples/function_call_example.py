"""
Function Call / Tool Use Example
llama-server must be started with --jinja flag (already included in serve scripts)

Requirements:
    pip install openai
"""

from openai import OpenAI
import json

client = OpenAI(
    base_url="http://127.0.0.1:8080/v1",
    api_key="not-needed"
)

# ─── define tools ────────────────────────────────────────────
tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get current weather for a given city",
            "parameters": {
                "type": "object",
                "properties": {
                    "city": {
                        "type": "string",
                        "description": "City name, e.g. Taipei"
                    },
                    "unit": {
                        "type": "string",
                        "enum": ["celsius", "fahrenheit"],
                        "description": "Temperature unit"
                    }
                },
                "required": ["city"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "search_web",
            "description": "Search the web for information",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query"
                    }
                },
                "required": ["query"]
            }
        }
    }
]

# ─── mock tool execution ─────────────────────────────────────
def execute_tool(name: str, args: dict) -> str:
    if name == "get_weather":
        city = args.get("city", "Unknown")
        unit = args.get("unit", "celsius")
        # replace with real API call
        return json.dumps({
            "city": city,
            "temperature": 25 if unit == "celsius" else 77,
            "unit": unit,
            "condition": "Sunny",
            "humidity": "60%"
        })
    if name == "search_web":
        query = args.get("query", "")
        # replace with real search API call
        return json.dumps({
            "query": query,
            "results": [
                {"title": "Example result 1", "url": "https://example.com/1"},
                {"title": "Example result 2", "url": "https://example.com/2"}
            ]
        })
    return json.dumps({"error": f"Unknown tool: {name}"})

# ─── agentic loop ────────────────────────────────────────────
def run(user_message: str):
    print(f"\nUser: {user_message}\n")
    messages = [{"role": "user", "content": user_message}]

    while True:
        response = client.chat.completions.create(
            model="gpt-oss-20b",
            messages=messages,
            tools=tools,
            tool_choice="auto",   # auto / none / required
            temperature=0.6,
            max_tokens=1024
        )

        msg = response.choices[0].message
        finish = response.choices[0].finish_reason

        # no tool call → final answer
        if finish == "stop" or not msg.tool_calls:
            print(f"Assistant: {msg.content}")
            return msg.content

        # model wants to call tools
        print(f"[Tool calls requested: {len(msg.tool_calls)}]")
        messages.append(msg)   # append assistant message with tool_calls

        for tc in msg.tool_calls:
            fn_name = tc.function.name
            fn_args = json.loads(tc.function.arguments)
            print(f"  -> {fn_name}({fn_args})")

            result = execute_tool(fn_name, fn_args)
            print(f"     result: {result}")

            messages.append({
                "role": "tool",
                "tool_call_id": tc.id,
                "content": result
            })

# ─── run examples ────────────────────────────────────────────
if __name__ == "__main__":
    run("What is the weather in Taipei right now?")
    run("Search for the latest news about llama.cpp")
    run("Compare weather between Tokyo and New York")
