/**
 * Chat controller for The Summit streaming via Mercure.
 *
 * This is a STANDALONE JavaScript module for Mercure-based streaming.
 * It's an alternative to the inline <script> in chatroom.html.twig - designed
 * for use with Symfony's Stimulus/AssetMapper if the project evolves to use it.
 *
 * For the current implementation (Milestone 4 sync + Milestone 5 streaming),
 * the template's inline <script> handles everything. This file provides a
 * reusable, importable version of the streaming logic.
 *
 * USAGE:
 *   import { initStreamingChat } from './chat_controller.js';
 *
 *   const stream = initStreamingChat(mercureUrl, sessionId, topicBase, container);
 *   // Later: stream.close() to clean up EventSource connections
 *
 * HOW IT WORKS:
 *   1. Creates EventSource connections to Mercure for each persona topic
 *   2. Creates chat bubbles dynamically when "start" events arrive
 *   3. Appends text tokens to bubbles as they arrive in real-time
 *   4. Removes "typing..." indicator when "complete" events arrive
 *   5. Cleans up all connections when the "done" event arrives
 */

// Visual configuration for each persona - matches the Tailwind classes in the template
const PERSONAS = {
    analyst:    { label: 'Analyst',    icon: '\ud83d\udcca', borderClass: 'border-l-blue-500',  bgClass: 'bg-blue-50',  textClass: 'text-blue-800',  badgeClass: 'bg-blue-100 text-blue-700' },
    skeptic:    { label: 'Skeptic',    icon: '\ud83e\udd28', borderClass: 'border-l-amber-500', bgClass: 'bg-amber-50', textClass: 'text-amber-800', badgeClass: 'bg-amber-100 text-amber-700' },
    strategist: { label: 'Strategist', icon: '\ud83e\udded', borderClass: 'border-l-green-500', bgClass: 'bg-green-50', textClass: 'text-green-800', badgeClass: 'bg-green-100 text-green-700' },
};

/**
 * Initialize streaming chat - subscribes to Mercure topics and renders tokens in real-time.
 *
 * @param {string}      mercureUrl       The public Mercure hub URL (e.g., http://localhost:3100/.well-known/mercure)
 * @param {string}      sessionId        The session UUID for conversation continuity
 * @param {string}      topicBase        The base Mercure topic (e.g., "the-summit/abc-123")
 * @param {HTMLElement}  messageContainer The DOM element to append chat bubbles to
 *
 * @returns {{ close: () => void }} An object with a close() method to clean up all EventSource connections
 */
export function initStreamingChat(mercureUrl, sessionId, topicBase, messageContainer) {
    // Track active EventSource connections so we can close them on cleanup
    const eventSources = {};
    // Track reconnect attempts per persona
    const retryCounts = {};
    // Track reconnect timers so they can be cancelled on cleanup
    const retryTimers = {};
    // Track whether a persona stream reached a terminal event
    const terminalStreams = {};
    // Track chat bubbles so we can append tokens to the right one
    const bubbles = {};
    // Retry policy for transient stream disconnects
    const MAX_RETRIES = 3;
    const BASE_RETRY_MS = 500;
    let doneEs = null;

    /**
     * Create an empty chat bubble for a persona - tokens will be appended via streaming.
     * The bubble includes a "typing..." indicator that's removed when streaming completes.
     */
    function createBubble(persona) {
        const config = PERSONAS[persona];
        const div = document.createElement('div');
        div.className = `border-l-4 ${config.borderClass} ${config.bgClass} rounded-r-lg p-4 max-w-3xl`;
        div.innerHTML = `
            <div class="flex items-center gap-2 mb-2">
                <span class="text-lg">${config.icon}</span>
                <span class="text-xs font-semibold px-2 py-0.5 rounded-full ${config.badgeClass}">${config.label}</span>
                <span class="typing-indicator text-xs ${config.textClass} opacity-60">typing...</span>
            </div>
            <div class="content markdown-content ${config.textClass} text-sm leading-relaxed"></div>
        `;
        messageContainer.appendChild(div);
        bubbles[persona] = div;
        return div;
    }

    function ensureBubble(persona) {
        if (!bubbles[persona]) {
            return createBubble(persona);
        }

        return bubbles[persona];
    }

    function removeTypingIndicator(persona) {
        if (!bubbles[persona]) {
            return;
        }

        const indicator = bubbles[persona].querySelector('.typing-indicator');
        if (indicator) {
            indicator.remove();
        }
    }

    function clearRetryTimer(persona) {
        if (retryTimers[persona]) {
            clearTimeout(retryTimers[persona]);
            delete retryTimers[persona];
        }
    }

    function closePersonaStream(persona) {
        clearRetryTimer(persona);
        if (eventSources[persona]) {
            eventSources[persona].close();
            delete eventSources[persona];
        }
    }

    function closeAllStreams() {
        ['analyst', 'skeptic', 'strategist'].forEach(closePersonaStream);
        if (doneEs) {
            doneEs.close();
        }
    }

    function failPersonaStream(persona, message) {
        const bubble = ensureBubble(persona);
        const contentEl = bubble.querySelector('.content');

        if (!contentEl.textContent) {
            contentEl.textContent = '';
        }

        contentEl.insertAdjacentText('beforeend', `\n\n[Stream error] ${message}`);
        removeTypingIndicator(persona);
    }

    function markAllStreamsFailed(message) {
        ['analyst', 'skeptic', 'strategist'].forEach((persona) => {
            if (!terminalStreams[persona]) {
                failPersonaStream(persona, message);
                terminalStreams[persona] = true;
            }
        });

        closeAllStreams();
    }

    /**
     * Subscribe to a single persona's Mercure topic via EventSource (SSE).
     *
     * EventSource is a browser API that opens a persistent connection to a server
     * and receives events as they're published. Mercure acts as the intermediary:
     *   PHP publishes to Mercure -> Mercure relays to EventSource -> onmessage fires
     *
     * Event types handled:
     *   "start"    - Create the chat bubble
     *   "text"     - Append token text to the bubble
     *   "complete" - Remove "typing..." indicator, close the connection
     *   "error"    - Show error message, close the connection
     */
    function subscribeTo(persona) {
        const topic = topicBase + '/' + persona;
        const url = new URL(mercureUrl);
        url.searchParams.append('topic', topic);

        function connect() {
            // Open an SSE connection to the Mercure hub for this topic
            const es = new EventSource(url);
            eventSources[persona] = es;

            es.onopen = () => {
                if (retryCounts[persona] > 0 && bubbles[persona]) {
                    const indicator = bubbles[persona].querySelector('.typing-indicator');
                    if (indicator) {
                        indicator.textContent = 'typing...';
                    }
                }
            };

            es.onmessage = (event) => {
                const data = JSON.parse(event.data);

                if (data.type === 'start') {
                    // Agent starting - create a chat bubble
                    ensureBubble(persona);
                } else if (data.type === 'text' && bubbles[persona]) {
                    // Text token - append to the bubble content
                    const contentEl = bubbles[persona].querySelector('.content');
                    contentEl.insertAdjacentText('beforeend', data.content);
                    // Auto-scroll to show the latest content
                    messageContainer.parentElement.scrollTop = messageContainer.parentElement.scrollHeight;
                } else if (data.type === 'complete') {
                    // Agent done - remove the typing indicator and close connection
                    terminalStreams[persona] = true;
                    removeTypingIndicator(persona);
                    closePersonaStream(persona);
                } else if (data.type === 'error') {
                    // Error - show the error in the bubble and close connection
                    terminalStreams[persona] = true;
                    failPersonaStream(persona, data.message || 'Unknown error');
                    closePersonaStream(persona);
                }
            };

            es.onerror = () => {
                if (terminalStreams[persona]) {
                    closePersonaStream(persona);
                    return;
                }

                closePersonaStream(persona);

                retryCounts[persona] = (retryCounts[persona] || 0) + 1;
                const attempt = retryCounts[persona];

                if (attempt <= MAX_RETRIES) {
                    const delayMs = BASE_RETRY_MS * (2 ** (attempt - 1));
                    const bubble = ensureBubble(persona);
                    const indicator = bubble.querySelector('.typing-indicator');
                    if (indicator) {
                        indicator.textContent = `reconnecting (${attempt}/${MAX_RETRIES})...`;
                    }

                    retryTimers[persona] = setTimeout(connect, delayMs);
                    return;
                }

                terminalStreams[persona] = true;
                markAllStreamsFailed('Connection lost and retries exhausted.');
            };
        }

        connect();
    }

    // Subscribe to all three persona topics
    ['analyst', 'skeptic', 'strategist'].forEach((persona) => {
        retryCounts[persona] = 0;
        terminalStreams[persona] = false;
        subscribeTo(persona);
    });

    // Also subscribe to the "done" topic - fires when ALL three agents are finished
    const doneUrl = new URL(mercureUrl);
    doneUrl.searchParams.append('topic', topicBase + '/done');
    doneEs = new EventSource(doneUrl);
    doneEs.onmessage = () => {
        ['analyst', 'skeptic', 'strategist'].forEach((persona) => {
            terminalStreams[persona] = true;
            removeTypingIndicator(persona);
        });

        closeAllStreams();
    };

    doneEs.onerror = () => {
        // If the completion stream itself fails, cleanly terminate all persona streams
        // and remove typing indicators so the UI does not stay in a loading state.
        markAllStreamsFailed('Completion channel disconnected.');
    };

    // Return a cleanup function for the caller
    return {
        /** Close all EventSource connections (call this when navigating away or resetting) */
        close() {
            closeAllStreams();
            ['analyst', 'skeptic', 'strategist'].forEach(removeTypingIndicator);
            Object.keys(retryTimers).forEach(clearRetryTimer);
        }
    };
}
