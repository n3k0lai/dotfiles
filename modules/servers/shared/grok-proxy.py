#!/usr/bin/env python3
"""
Simple HTTP proxy to make Grok API OpenAI-compatible for OpenClaw
"""
import json
import asyncio
import aiohttp
from aiohttp import web
import os

XAI_API_KEY = os.environ.get("XAI_API_KEY", "")
XAI_BASE_URL = "https://api.x.ai/v1"

# Map OpenAI-style model names to Grok models
MODEL_MAP = {
    "gpt-4o": "grok-4-1-fast-reasoning",
    "gpt-4o-mini": "grok-4-1-fast-non-reasoning", 
    "gpt-4-code": "grok-code-fast-1",
    "grok-reasoning": "grok-4-1-fast-reasoning",
    "grok-fast": "grok-4-1-fast-non-reasoning",
    "grok-code": "grok-code-fast-1"
}

async def proxy_chat_completions(request):
    try:
        data = await request.json()
        
        # Map model name
        requested_model = data.get("model", "gpt-4o")
        grok_model = MODEL_MAP.get(requested_model, "grok-4-1-fast-reasoning")
        data["model"] = grok_model
        
        async with aiohttp.ClientSession() as session:
            headers = {
                "Authorization": f"Bearer {XAI_API_KEY}",
                "Content-Type": "application/json"
            }
            
            async with session.post(
                f"{XAI_BASE_URL}/chat/completions",
                json=data,
                headers=headers
            ) as resp:
                if resp.status == 200:
                    response_data = await resp.json()
                    return web.json_response(response_data)
                else:
                    error_text = await resp.text()
                    return web.json_response(
                        {"error": {"message": f"Grok API error: {error_text}"}},
                        status=resp.status
                    )
                    
    except Exception as e:
        return web.json_response(
            {"error": {"message": f"Proxy error: {str(e)}"}},
            status=500
        )

async def list_models(request):
    """Return available models in OpenAI format"""
    models = [
        {"id": "gpt-4o", "object": "model", "owned_by": "grok-proxy"},
        {"id": "gpt-4o-mini", "object": "model", "owned_by": "grok-proxy"},
        {"id": "gpt-4-code", "object": "model", "owned_by": "grok-proxy"},
        {"id": "grok-reasoning", "object": "model", "owned_by": "grok-proxy"},
        {"id": "grok-fast", "object": "model", "owned_by": "grok-proxy"},
        {"id": "grok-code", "object": "model", "owned_by": "grok-proxy"},
    ]
    return web.json_response({"object": "list", "data": models})

async def health_check(request):
    return web.json_response({"status": "healthy", "proxy": "grok-openai"})

def create_app():
    app = web.Application()
    app.router.add_post('/v1/chat/completions', proxy_chat_completions)
    app.router.add_get('/v1/models', list_models)
    app.router.add_get('/health', health_check)
    return app

if __name__ == '__main__':
    app = create_app()
    print("Starting Grok → OpenAI proxy on http://127.0.0.1:8001")
    web.run_app(app, host='127.0.0.1', port=8001)