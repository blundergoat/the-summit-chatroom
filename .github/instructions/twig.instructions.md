---
applyTo: 'templates/**/*.twig'
---

# Twig / Frontend Conventions - The Summit

## Structure

- Single template: `templates/chatroom.html.twig`
- Inline JavaScript (no build step, no bundler)
- CSS via inline `<style>` blocks

## Dual-Mode UI

The template must support both execution modes:

- **Sync mode**: `fetch()` to `POST /chat`, render complete JSON response
- **Streaming mode**: `fetch()` returns a Mercure topic, subscribe via `EventSource`, render tokens as they arrive

Always handle both paths. Never assume Mercure is available — check for the topic URL in the response before opening an EventSource.

## Conventions

- Use Symfony's `{{ path('route_name') }}` for URLs, not hardcoded paths
- Use `{{ mercure_public_url }}` from Twig globals for Mercure, not hardcoded URLs
- Escape user content with `{{ message|e }}` to prevent XSS
- JavaScript uses `const`/`let` (no `var`), arrow functions, template literals

## Character Display

- Each character has a distinct colour and avatar assigned by the frontend
- Three characters are randomly selected per session from a roster of 10
- The persona name comes from the API response — display it, don't hardcode the roster in the template

## Error Handling

- Sync mode: catch `fetch()` errors, show user-facing message
- Streaming mode: handle `EventSource.onerror`, fall back to sync if connection fails
- Show a loading state while agents are responding (~30s for sync, real-time for streaming)
