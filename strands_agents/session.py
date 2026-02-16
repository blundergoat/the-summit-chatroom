"""
In-memory session store for conversation history.

=============================================================================
WHAT THIS FILE DOES
=============================================================================

This module stores conversation history as role/content message pairs,
compatible with LLM APIs (which expect a "messages" array format).

When the PHP app sends a user question to the summit, the SAME message is
sent to all three agents (analyst, skeptic, strategist). The session store:

  1. Deduplicates the user message (stored once, not three times)
  2. Accumulates each agent's response with persona metadata
  3. Provides the full history to each subsequent agent

This is how the "debate" works:
  - Analyst sees: [user question]
  - Skeptic sees: [user question, analyst's response]
  - Strategist sees: [user question, analyst's response, skeptic's response]

=============================================================================
DATA STRUCTURE
=============================================================================

Each session is a list of message dicts:

  [
      {"role": "user",      "content": "Should we migrate to microservices?"},
      {"role": "assistant", "content": "BLUF: 60-70% chance of success...", "metadata": {"persona": "analyst"}},
      {"role": "assistant", "content": "Three red flags in that analysis...", "metadata": {"persona": "skeptic"}},
      {"role": "assistant", "content": "Recommended path: start with...",    "metadata": {"persona": "strategist"}},
  ]

=============================================================================
LIMITATIONS (this is a POC)
=============================================================================

  - IN-MEMORY ONLY: All history is lost when the container restarts.
    For production, use Redis, DynamoDB, or a database.

  - NAIVE DEDUPLICATION: Checks if the last message has identical content.
    This handles the multi-agent round pattern but would incorrectly dedup
    a legitimate follow-up with identical text. A proper solution would use
    round IDs or idempotency keys.
"""

from collections import defaultdict


class SessionStore:
    """Thread-safe (for async) in-memory conversation history store.

    Stores messages as role/content pairs with optional persona metadata.
    One instance is shared across all requests in the FastAPI server.
    """

    def __init__(self) -> None:
        # defaultdict(list) creates an empty list for new session IDs automatically
        self._sessions: dict[str, list[dict]] = defaultdict(list)

    def append_user(self, session_id: str, content: str) -> None:
        """Append a user message to the session, with deduplication.

        WHY DEDUPLICATION:
        The PHP orchestrator sends the SAME user message to all three agents
        (analyst, skeptic, strategist). Without dedup, the session would contain
        the same user message three times, confusing the LLM.

        The dedup check: if the last message in the session is a user message
        with identical content, skip the append.

        Args:
            session_id: The session UUID
            content: The user's message text
        """
        history = self._sessions[session_id]
        if history and history[-1]["role"] == "user" and history[-1]["content"] == content:
            return  # Already stored — skip duplicate
        history.append({"role": "user", "content": content})

    def append_assistant(self, session_id: str, content: str, persona: str) -> None:
        """Append an assistant (agent) response to the session.

        Each response is tagged with the persona name in metadata so we can
        tell which agent said what when building the history for the next agent.

        Args:
            session_id: The session UUID
            content: The agent's response text
            persona: Which persona generated this response (analyst/skeptic/strategist)
        """
        self._sessions[session_id].append({
            "role": "assistant",
            "content": content,
            "metadata": {"persona": persona},
        })

    def get_messages(self, session_id: str) -> list[dict]:
        """Return the session history as a messages array for the LLM.

        LLMs expect a list of {"role": "user"|"assistant", "content": "..."} dicts.
        This method builds that array from the session history.

        Assistant messages are prefixed with a natural-language attribution so
        subsequent agents know who said what. We use "(Name said)" rather than
        "[NAME]:" because the bracket format causes smaller LLMs to mimic it
        in their own output.

        Example output:
            [
                {"role": "user", "content": "Should we migrate?"},
                {"role": "assistant", "content": "(Gandalf said) Not all who wander..."},
                {"role": "assistant", "content": "(Terminator said) Probability of..."},
            ]

        Args:
            session_id: The session UUID

        Returns:
            A list of role/content message dicts ready for the LLM.
        """
        messages = []
        for turn in self._sessions.get(session_id, []):
            content = turn["content"]
            # Prefix assistant messages with natural-language attribution
            if turn["role"] == "assistant" and turn.get("metadata", {}).get("persona"):
                name = turn["metadata"]["persona"].replace("_", " ").title()
                content = f"({name} said) {content}"
            messages.append({"role": turn["role"], "content": content})
        return messages

    def format_history_as_prompt(self, session_id: str) -> str:
        """Format the full session history as a single string prompt.

        This is an alternative to get_messages() for when the agent invocation
        pattern requires a single string instead of a messages array.
        Currently not used by the server (we use native messages arrays),
        but kept for compatibility.

        Args:
            session_id: The session UUID

        Returns:
            A formatted string with all turns labeled by role/persona.
        """
        history = self._sessions.get(session_id, [])
        if not history:
            return ""

        # If there's only one entry (the current user message), return it directly
        if len(history) == 1:
            return history[0]["content"]

        parts = []
        for i, turn in enumerate(history):
            if turn["role"] == "user":
                parts.append(f"User: {turn['content']}")
            elif turn["role"] == "assistant":
                persona = turn.get("metadata", {}).get("persona", "assistant")
                name = persona.replace("_", " ").title()
                parts.append(f"({name} said) {turn['content']}")

        return "\n\n".join(parts)

    def get_full_history(self, session_id: str) -> list[dict]:
        """Return the raw session history with metadata (for the /session/{id}/history endpoint).

        Unlike get_messages(), this returns the raw data including metadata fields.
        Useful for debugging.

        Args:
            session_id: The session UUID

        Returns:
            A list of raw message dicts with metadata.
        """
        return list(self._sessions.get(session_id, []))
