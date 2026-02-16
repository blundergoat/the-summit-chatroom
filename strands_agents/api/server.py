"""
FastAPI server for The Summit multi-persona agent.

=============================================================================
WHAT THIS FILE DOES
=============================================================================

This is the HTTP API that the PHP application talks to. It exposes three endpoints:

  POST /invoke              — Synchronous: send a message, get a complete response
  POST /stream              — Streaming: send a message, get tokens via Server-Sent Events (SSE)
  GET  /session/{id}/history — Debug: view a session's conversation history
  GET  /health              — Health check for Docker's healthcheck probe

=============================================================================
HOW THE PHP APP USES THIS
=============================================================================

The PHP StrandsClient sends HTTP requests to this server:

  SYNC MODE (invoke):
    PHP sends POST /invoke with { message, session_id, context: { metadata: { persona } } }
    Python creates an Agent with the right persona, calls the LLM, returns the full text.

  STREAMING MODE (stream):
    PHP sends POST /stream with the same payload.
    Python creates an Agent, streams tokens from the LLM, and sends each token as an SSE event.
    The PHP app's StreamParser reads these events and forwards them to Mercure.

=============================================================================
SESSION MANAGEMENT
=============================================================================

The SessionStore maintains conversation history per session_id. When the PHP app
sends the same message to all three agents (analyst, skeptic, strategist), the
session store deduplicates the user message and accumulates assistant responses.

This means:
  - Analyst sees: [user message]
  - Skeptic sees: [user message, analyst's response]
  - Strategist sees: [user message, analyst's response, skeptic's response]

This is what makes it a real debate — each agent builds on the previous ones.

=============================================================================
SSE EVENT CONTRACT
=============================================================================

The streaming endpoint emits these event types (the PHP StreamParser expects them):

  { "type": "text",        "content": "token text" }      — A piece of generated text
  { "type": "thinking" }                                    — Agent is reasoning
  { "type": "tool_use",    "tool_name": "search" }         — Agent is calling a tool
  { "type": "tool_result", "tool_name": "search" }         — Tool returned a result
  { "type": "complete",    "text": "full response" }       — Stream finished successfully
  { "type": "error",       "message": "what went wrong" }  — Stream failed

Every stream is GUARANTEED to end with either "complete" or "error".
"""

import json

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from agents import create_agent, get_personas
from sabotage import SabotageEngine
from session import SessionStore

# Create the FastAPI application instance
app = FastAPI(title="The Summit Agent", version="0.1.0")

# In-memory session store — conversation history lives here.
# NOTE: This is lost when the container restarts. For production,
# you'd use Redis, DynamoDB, or a database instead.
sessions = SessionStore()

# Sabotage engine — manages secret objective assignment per round.
# Shared across all requests, tracks round decisions and cooldowns.
sabotage_engine = SabotageEngine()


# =============================================================================
# PYDANTIC MODELS — Define the shape of request/response JSON
# =============================================================================
# Pydantic automatically validates incoming JSON against these schemas.
# If a required field is missing or has the wrong type, FastAPI returns 422.

class RequestContext(BaseModel):
    """Context sent with each request — contains metadata like the persona name."""
    system_prompt: str | None = None    # Optional system prompt override (not used currently)
    metadata: dict = Field(default_factory=dict)  # Arbitrary key-value pairs (e.g., {"persona": "analyst"})


class InvokeRequest(BaseModel):
    """The request body for /invoke and /stream endpoints."""
    message: str                        # The user's question or message
    session_id: str | None = None       # UUID for conversation continuity (None = one-shot)
    context: RequestContext = Field(default_factory=RequestContext)


class UsageStats(BaseModel):
    """Token usage statistics (for cost tracking — not implemented yet)."""
    input_tokens: int = 0
    output_tokens: int = 0


class InvokeResponse(BaseModel):
    """The response body for the /invoke endpoint."""
    text: str                           # The agent's complete response text
    agent: str                          # Which persona generated this response
    session_id: str | None = None       # Echo back the session ID
    usage: UsageStats = Field(default_factory=UsageStats)
    tools_used: list = Field(default_factory=list)


# =============================================================================
# SSE EVENT MAPPING
# =============================================================================
# The Strands SDK emits various event types during streaming. We map them to
# our canonical event contract (documented above) so the PHP client has a
# stable, well-defined API to consume.

def map_sdk_event(sdk_event) -> dict | None:
    """Map a Strands SDK streaming event to our canonical SSE event format.

    The SDK may emit events as dicts, objects with to_dict(), or plain strings.
    We normalize them into our contract format.

    Args:
        sdk_event: A streaming event from the Strands SDK

    Returns:
        A dict matching our SSE event contract, or None if the event should be skipped.
    """
    # Normalize the SDK event into a dict
    if isinstance(sdk_event, dict):
        raw = sdk_event
    elif hasattr(sdk_event, "to_dict"):
        raw = sdk_event.to_dict()
    else:
        # Plain string chunk — not a structured event, will be handled by the caller
        return None

    # Only forward event types that are in our contract
    event_type = raw.get("type", "")
    if event_type in ("text", "tool_use", "tool_result", "thinking", "complete", "error"):
        return raw
    return None


def build_complete_event(text: str, session_id: str | None) -> str:
    """Build the terminal 'complete' SSE event as a JSON string.

    This is sent at the end of every stream to signal that streaming is done.
    It includes the full concatenated text so the client can use it if needed.
    """
    return json.dumps({
        "type": "complete",
        "text": text,
        "session_id": session_id,
        "usage": {},
        "tools_used": [],
    })


# =============================================================================
# HELPERS
# =============================================================================

def _build_messages(session_id: str | None, message: str) -> list[dict]:
    """Build the messages array for agent invocation.

    LLMs work with "messages" — a list of role/content pairs representing
    the conversation history. This function:
      1. Appends the user's message to the session history (with deduplication)
      2. Returns the full history as a messages array
      3. Converts content to Strands SDK format: content must be list[ContentBlock]
         (e.g., [{"text": "..."}]), not plain strings

    For one-shot requests (no session_id), returns a single-turn array.

    Args:
        session_id: The session UUID (None for one-shot conversations)
        message: The user's message text

    Returns:
        A list of Strands SDK-compatible message dicts with role and content fields.
    """
    if session_id:
        sessions.append_user(session_id, message)
        raw_messages = sessions.get_messages(session_id)
    else:
        raw_messages = [{"role": "user", "content": message}]

    return _to_sdk_messages(raw_messages)


def _to_sdk_messages(messages: list[dict]) -> list[dict]:
    """Convert plain-text messages to Strands SDK message format.

    The Strands SDK Agent expects messages where 'content' is a list of
    ContentBlock dicts (e.g., [{"text": "hello"}]), not a plain string.
    The session store uses plain strings for simplicity, so we convert here.

    Args:
        messages: Messages with string content fields.

    Returns:
        Messages with content converted to [{"text": "..."}] format.
    """
    sdk_messages = []
    for msg in messages:
        content = msg["content"]
        if isinstance(content, str):
            content = [{"text": content}]
        sdk_messages.append({"role": msg["role"], "content": content})
    return sdk_messages


# =============================================================================
# ENDPOINTS
# =============================================================================

@app.post("/invoke", response_model=InvokeResponse)
async def invoke(req: InvokeRequest):
    """Synchronous invocation — blocks until the agent generates a complete response.

    Flow:
      1. Extract the persona from request context metadata
      2. Create an Agent with the persona's system prompt
      3. Build the messages array (with session history if applicable)
      4. Call the LLM and wait for the full response
      5. Save the response to the session store
      6. Return the complete text

    Used by the PHP SummitOrchestrator in sync mode.
    """
    # Get the persona from the request context (default to "analyst" if not specified)
    persona = req.context.metadata.get("persona", "analyst")
    if persona not in get_personas():
        raise HTTPException(status_code=400, detail=f"Unknown persona: {persona}")

    # Check for a secret objective — the sabotage engine uses the correlation_id
    # (shared across all 3 persona requests in a round) to make one decision per round.
    correlation_id = req.context.metadata.get("correlation_id", "")
    active_personas = req.context.metadata.get("active_personas", [persona])
    objective_prompt = None
    if req.session_id and correlation_id:
        objective_prompt = sabotage_engine.get_objective_for_persona(
            session_id=req.session_id,
            correlation_id=correlation_id,
            persona=persona,
            active_personas=active_personas,
        )

    # Create an Agent instance with the persona's system prompt
    # (and secret objective appended, if this persona was selected for sabotage)
    try:
        agent = create_agent(persona, objective_prompt)
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))

    # Build the conversation history + current message (in SDK-compatible format)
    messages = _build_messages(req.session_id, req.message)

    # Call the agent — this blocks until the LLM generates the full response.
    # Pass messages as the first positional arg (the 'prompt' parameter).
    # The SDK accepts list[Message] as prompt for multi-turn conversations.
    response = agent(messages)
    response_text = str(response)

    # Save the assistant's response to the session for future turns
    if req.session_id:
        sessions.append_assistant(req.session_id, response_text, persona)

    return InvokeResponse(
        text=response_text,
        agent=persona,
        session_id=req.session_id,
    )


@app.post("/stream")
async def stream(req: InvokeRequest):
    """Streaming invocation — returns tokens as Server-Sent Events (SSE).

    Instead of waiting for the full response, this endpoint streams each token
    as it's generated by the LLM. The response uses the "text/event-stream"
    content type (SSE protocol).

    Flow:
      1. Extract persona, create agent, build messages (same as /invoke)
      2. Call agent.stream_async() which yields events as the LLM generates tokens
      3. Map each SDK event to our SSE contract format
      4. Yield each event as an SSE "data:" line
      5. Guarantee a terminal event (complete or error) at the end

    Used by the PHP SummitStreamOrchestrator's stream() method.
    """
    persona = req.context.metadata.get("persona", "analyst")
    if persona not in get_personas():
        raise HTTPException(status_code=400, detail=f"Unknown persona: {persona}")

    # Check for a secret objective (same logic as /invoke)
    correlation_id = req.context.metadata.get("correlation_id", "")
    active_personas = req.context.metadata.get("active_personas", [persona])
    objective_prompt = None
    if req.session_id and correlation_id:
        objective_prompt = sabotage_engine.get_objective_for_persona(
            session_id=req.session_id,
            correlation_id=correlation_id,
            persona=persona,
            active_personas=active_personas,
        )

    try:
        agent = create_agent(persona, objective_prompt)
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))

    messages = _build_messages(req.session_id, req.message)

    async def event_generator():
        """Async generator that yields SSE events as the LLM streams tokens.

        SSE FORMAT:
          Each event is a line starting with "data: " followed by JSON, then two newlines.
          Example: data: {"type": "text", "content": "Hello"}\n\n

        The generator guarantees that every stream ends with either a "complete"
        or "error" event, even if the SDK doesn't emit one.
        """
        full_text = ""        # Accumulate the full response text
        got_terminal = False  # Track whether we've sent a complete/error event

        try:
            # agent.stream_async() returns an async iterator that yields events
            # as the LLM produces tokens. Pass messages as the first positional
            # arg (the 'prompt' parameter) — NOT as a keyword arg.
            async for sdk_event in agent.stream_async(messages):
                # Try to map the SDK event to our canonical format
                canonical = map_sdk_event(sdk_event)
                if canonical:
                    # Known structured event — forward it as SSE
                    yield f"data: {json.dumps(canonical)}\n\n"
                    if canonical.get("type") == "text":
                        full_text += canonical.get("content", "")
                    if canonical.get("type") in ("complete", "error"):
                        got_terminal = True
                elif isinstance(sdk_event, str):
                    # Plain string chunk from the SDK — wrap it as a "text" event
                    full_text += sdk_event
                    yield f"data: {json.dumps({'type': 'text', 'content': sdk_event})}\n\n"
                elif isinstance(sdk_event, dict) and "data" in sdk_event:
                    # Legacy format: {"data": "text chunk"} — normalize to our format
                    chunk = str(sdk_event["data"])
                    full_text += chunk
                    yield f"data: {json.dumps({'type': 'text', 'content': chunk})}\n\n"

            # Save the complete response to the session store
            if req.session_id:
                sessions.append_assistant(req.session_id, full_text, persona)

            # GUARANTEE: Every stream must end with "complete" or "error".
            # If the SDK didn't emit a terminal event, we send one now.
            if not got_terminal:
                yield f"data: {build_complete_event(full_text, req.session_id)}\n\n"
        except Exception as e:
            # If streaming fails (network error, LLM crash, etc.),
            # send an error event so the PHP client knows what happened.
            if not got_terminal:
                yield f"data: {json.dumps({'type': 'error', 'code': 'INTERNAL', 'message': str(e)})}\n\n"

    # Return a streaming HTTP response with SSE content type
    return StreamingResponse(event_generator(), media_type="text/event-stream")


@app.get("/session/{session_id}/history")
async def session_history(session_id: str):
    """Debug endpoint — view the full conversation history for a session.

    Useful for debugging to see what the agents have said so far.
    Not used by the PHP application in normal operation.
    """
    return {"session_id": session_id, "turns": sessions.get_full_history(session_id)}


@app.get("/health")
async def health():
    """Health check endpoint — used by Docker's healthcheck to verify the agent is running.

    Docker Compose's healthcheck calls this every 10 seconds. If it fails 3 times
    in a row, Docker marks the container as unhealthy and dependent services
    won't start (see docker-compose.yml).
    """
    return {"status": "ok"}
