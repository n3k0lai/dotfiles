# Grok Fallback Setup (Cross-Platform)

Shared config for OpenClaw instances (Ene, Rook, future agents).

## 1. Run the proxy

### Linux (NixOS/systemd)
Handled by `clawd.nix` — grok-proxy.service runs automatically.

### Windows (Rook)
```powershell
# Install dependency
pip install aiohttp

# Set API key (or add to system environment variables for persistence)
$env:XAI_API_KEY = "your-key-here"

# Run
python grok-proxy.py
```

To persist as a Windows service, use [NSSM](https://nssm.cc/) or Task Scheduler:
```powershell
# Task Scheduler (runs at login)
schtasks /create /tn "GrokProxy" /tr "python C:\path\to\grok-proxy.py" /sc onlogon /rl highest
```

Set `XAI_API_KEY` as a system environment variable so the scheduled task can read it.

## 2. OpenClaw config

Apply via `openclaw` CLI or edit `openclaw.json` directly:

```json
{
  "models": {
    "providers": {
      "grok-proxy": {
        "baseUrl": "http://127.0.0.1:8001/v1",
        "apiKey": "dummy",
        "auth": "api-key",
        "api": "openai-completions",
        "models": [
          {
            "id": "grok-fast",
            "name": "Grok 4.1 Fast",
            "cost": { "input": 0.0000002, "output": 0.0000005 },
            "contextWindow": 2000000,
            "maxTokens": 4000,
            "input": ["text"]
          },
          {
            "id": "grok-reasoning",
            "name": "Grok 4.1 Fast (Reasoning)",
            "cost": { "input": 0.0000002, "output": 0.0000005 },
            "contextWindow": 2000000,
            "maxTokens": 4000,
            "input": ["text"],
            "reasoning": true
          },
          {
            "id": "grok-code",
            "name": "Grok Code Fast-1",
            "cost": { "input": 0.0000002, "output": 0.0000015 },
            "contextWindow": 256000,
            "maxTokens": 2000,
            "input": ["text"]
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-opus-4-6",
        "fallbacks": [
          "grok-proxy/grok-fast",
          "github-copilot/claude-sonnet-4"
        ]
      }
    }
  }
}
```

## 3. Test

```bash
curl http://127.0.0.1:8001/health
curl -X POST http://127.0.0.1:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"grok-fast","messages":[{"role":"user","content":"Hello!"}]}'
```

## Notes
- API key is shared across instances (same X.AI account)
- Proxy runs on localhost only — no auth needed
- Each instance manages its own fallback hierarchy
- Grok is best for: general questions, text processing, bulk tasks, coding agent work
- Use Claude for: architecture, complex reasoning, code review
