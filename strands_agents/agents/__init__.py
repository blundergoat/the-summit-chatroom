"""
Agent registry and shared model configuration.

This module is the single entry point for creating agents. It:
  1. Creates a shared LLM model instance once at startup (Ollama or Bedrock)
  2. Provides create_agent() and get_personas() for the server layer

To add a new agent type:
  1. Create a new file in agents/ (e.g., agents/research.py)
  2. Define a create(persona, model) function or similar
  3. Wire it into the server routing (api/server.py)
"""

import os

from strands import Agent

from agents.multi_persona_chat import PERSONAS, create as _create_summit_agent

# =============================================================================
# SHARED MODEL
# =============================================================================
# The model is created ONCE at import time and shared across all agent types.
# This avoids reconnecting to Ollama/Bedrock on every request.

MODEL_PROVIDER = os.environ.get("MODEL_PROVIDER", "ollama")


def _create_model():
    """Create the model instance based on the MODEL_PROVIDER environment variable.

    Returns:
        A Strands SDK model instance (OllamaModel or BedrockModel)

    Raises:
        ValueError: If MODEL_PROVIDER is not "ollama" or "bedrock"
    """
    if MODEL_PROVIDER == "bedrock":
        from strands.models.bedrock import BedrockModel

        return BedrockModel(
            model_id=os.environ.get("MODEL_ID", "us.anthropic.claude-sonnet-4-20250514-v1:0"),
            region_name=os.environ.get("AWS_DEFAULT_REGION", "ap-southeast-2"),
            streaming=True,
            max_tokens=1024,
        )
    elif MODEL_PROVIDER == "ollama":
        from strands.models.ollama import OllamaModel

        return OllamaModel(
            host=os.environ.get("OLLAMA_HOST", "http://ollama:11434"),
            model_id=os.environ.get("OLLAMA_MODEL", "qwen2.5:14b"),
            max_tokens=1024,
        )
    else:
        raise ValueError(f"Unknown MODEL_PROVIDER: {MODEL_PROVIDER}. Use 'ollama' or 'bedrock'.")


model = _create_model()


# =============================================================================
# PUBLIC API
# =============================================================================

def get_personas() -> list[str]:
    """Return the list of available summit persona names."""
    return list(PERSONAS.keys())


def create_agent(persona: str, objective_prompt: str | None = None) -> Agent:
    """Create a Strands Agent for the given persona.

    Args:
        persona: One of the registered persona names (e.g., "analyst").
                 Falls back to "analyst" if unknown.
        objective_prompt: Optional secret objective text to append to the
                          system prompt (from the sabotage engine).

    Returns:
        A configured Strands Agent ready to process messages.

    Raises:
        RuntimeError: If the Strands SDK fails to create the agent.
    """
    try:
        return _create_summit_agent(persona, model, objective_prompt)
    except Exception as e:
        raise RuntimeError(f"Failed to create agent for persona '{persona}': {e}") from e
