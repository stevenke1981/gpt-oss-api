#!/usr/bin/env bash
# Function Call via curl
# llama-server must be running with --jinja flag

BASE_URL="http://127.0.0.1:8080"

echo "=== Single tool call ==="
curl -s "${BASE_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [
      {"role": "user", "content": "What is the weather in Taipei?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get current weather for a city",
          "parameters": {
            "type": "object",
            "properties": {
              "city": {"type": "string", "description": "City name"},
              "unit": {"type": "string", "enum": ["celsius","fahrenheit"]}
            },
            "required": ["city"]
          }
        }
      }
    ],
    "tool_choice": "auto",
    "temperature": 0.6,
    "max_tokens": 512
  }' | python3 -m json.tool

echo ""
echo "=== Force specific tool ==="
curl -s "${BASE_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [
      {"role": "user", "content": "Tell me about llama.cpp"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "search_web",
          "description": "Search the web",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {"type": "string"}
            },
            "required": ["query"]
          }
        }
      }
    ],
    "tool_choice": {"type": "function", "function": {"name": "search_web"}},
    "temperature": 0.6,
    "max_tokens": 512
  }' | python3 -m json.tool
