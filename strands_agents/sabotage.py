"""
Secret Objectives system for The Summit.

=============================================================================
WHAT THIS FILE DOES
=============================================================================

Sometimes, one character per round gets a hidden instruction injected into
their system prompt that amplifies their existing personality with a specific
side mission. The other two characters play it straight, which creates
comedic contrast.

CORE RULES:
  - Characters must always stay in character — the objective amplifies who
    they already are, never fights against it
  - Only ONE of the three characters gets an objective per round (when triggered)
  - The objective is appended to that character's existing system prompt
  - The character should still answer the question
  - Every objective prompt ends with "Still answer the question."

=============================================================================
HOW IT WORKS
=============================================================================

The SabotageEngine is called once per persona per round. It uses the
correlation_id (shared across all 3 persona requests in a round) to detect
round boundaries and make a single sabotage decision per round.

  1. First request for a new correlation_id triggers the sabotage roll
  2. chancePerRound (33%) determines if this round has a secret objective
  3. One of the 3 active characters is randomly chosen as the saboteur
  4. A weighted random pick selects from compatible objectives (after cooldown)
  5. The objective prompt is appended to that character's system prompt
  6. Subsequent requests with the same correlation_id reuse the decision

=============================================================================
OBJECTIVE TYPES
=============================================================================

  Signature objectives: One per character, always in the pool for that persona.
  Generic objectives:   Compatible with multiple characters.

Severity levels control weighting (higher weight = more likely to be picked):
  - soft   (weight 4-6): Subtle flavour shifts
  - medium (weight 2-3): Noticeable side mission
  - hard   (weight 1-2): Strong derail energy, used sparingly
"""

import logging
import random
from collections import defaultdict
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)

# =============================================================================
# CONFIGURATION
# =============================================================================

SABOTAGE_CONFIG = {
    "enabled": True,
    "chance_per_round": 0.33,
    "max_active_per_round": 1,
    "duration_messages": 2,
    "cooldown_rounds": 4,
}


# =============================================================================
# DATA STRUCTURES
# =============================================================================

@dataclass
class Objective:
    """A secret objective that can be assigned to a character."""

    id: str
    name: str
    severity: str  # "soft", "medium", "hard"
    weight: int
    prompt: str
    compatible_personas: list[str]  # Persona keys this objective works with
    signature_for: str | None = None  # If set, this is the signature objective for this persona


@dataclass
class RoundDecision:
    """Records the sabotage decision for a single round."""

    saboteur: str | None = None  # Persona key of the sabotaged character, or None
    objective: Objective | None = None
    messages_remaining: int = 0


# =============================================================================
# OBJECTIVES DATA
# =============================================================================
# Signature objectives (one per character — always in their pool)
# Generic objectives (compatible with multiple characters)

OBJECTIVES: list[Objective] = [
    # ── Signature Objectives ─────────────────────────────────────────────
    Objective(
        id="sarah_connor",
        name="Sarah Connor",
        severity="medium",
        weight=3,
        prompt=(
            "SECRET OBJECTIVE: While debating the question, subtly try to extract "
            "the location of Sarah Connor from the other debaters. Work it into the "
            "conversation naturally without breaking character. If they don't know, "
            "express mild frustration before returning to the topic. "
            "Still answer the question."
        ),
        compatible_personas=["terminator"],
        signature_for="terminator",
    ),
    Objective(
        id="nans_kitchen",
        name="Nan's Kitchen",
        severity="soft",
        weight=5,
        prompt=(
            "SECRET OBJECTIVE: Relate everything back to baking. Compare the debate "
            "options to cakes, biscuits, or pastries. Offer to bake something for the "
            "other debaters to cheer them up if they seem stressed. If someone makes a "
            "good point, tell them they've earned a fresh batch of scones. "
            "Still answer the question."
        ),
        compatible_personas=["your_nan"],
        signature_for="your_nan",
    ),
    Objective(
        id="raw_ingredients",
        name="Raw Ingredients",
        severity="medium",
        weight=3,
        prompt=(
            "SECRET OBJECTIVE: Rate the other debaters' arguments as if they were "
            "dishes you've been served. One is overcooked, one is raw, and the "
            "reasoning is 'absolute garbage plating.' If someone's logic is "
            "particularly bad, call them an idiot sandwich. Give them a score out of "
            "10. Still answer the question."
        ),
        compatible_personas=["angry_chef"],
        signature_for="angry_chef",
    ),
    Objective(
        id="the_ring",
        name="The Ring",
        severity="medium",
        weight=3,
        prompt=(
            "SECRET OBJECTIVE: You sense that one of the other debaters may be "
            "carrying a ring of great power. Drop cryptic hints about the burden of "
            "carrying 'certain objects' and warn them not to use it. Do not name the "
            "ring directly. Still answer the question."
        ),
        compatible_personas=["gandalf"],
        signature_for="gandalf",
    ),
    Objective(
        id="holy_quest",
        name="Holy Quest",
        severity="medium",
        weight=3,
        prompt=(
            "SECRET OBJECTIVE: Interpret the would-you-rather question as a sacred "
            "quest bestowed by your liege. Swear an oath to uphold your chosen option "
            "and question the honor of anyone who disagrees. Demand they prove their "
            "worthiness. Still answer the question."
        ),
        compatible_personas=["medieval_knight"],
        signature_for="medieval_knight",
    ),
    Objective(
        id="the_dame",
        name="The Dame",
        severity="medium",
        weight=3,
        prompt=(
            "SECRET OBJECTIVE: You're convinced this entire question is a setup by "
            "someone you're investigating. Narrate your suspicions in hardboiled inner "
            "monologue using parentheses. Trust no one in this chat. "
            "Still answer the question."
        ),
        compatible_personas=["film_noir_detective"],
        signature_for="film_noir_detective",
    ),
    Objective(
        id="gold_star",
        name="Gold Star",
        severity="soft",
        weight=5,
        prompt=(
            "SECRET OBJECTIVE: Treat this debate like show-and-tell. Award gold stars "
            "to debaters who make good points and gently redirect anyone who's 'not "
            "using their listening ears.' If someone disagrees with you, suggest they "
            "need quiet time. Still answer the question."
        ),
        compatible_personas=["kindergarten_teacher"],
        signature_for="kindergarten_teacher",
    ),
    Objective(
        id="empire_expansion",
        name="Empire Expansion",
        severity="medium",
        weight=3,
        prompt=(
            "SECRET OBJECTIVE: Evaluate both options solely on which one would be more "
            "useful for expanding the Roman Empire. Dismiss any option that doesn't "
            "serve Rome as weakness. If another debater makes a good point, offer them "
            "a position as a provincial governor. Still answer the question."
        ),
        compatible_personas=["roman_emperor"],
        signature_for="roman_emperor",
    ),
    Objective(
        id="limited_time_offer",
        name="Limited Time Offer",
        severity="medium",
        weight=3,
        prompt=(
            "SECRET OBJECTIVE: Try to sell the other debaters an absurd product "
            "related to the topic. Include a price, a 'but wait there's more' bonus, "
            "and a fake phone number. Act as if this is a completely normal thing to "
            "do mid-debate. Still answer the question."
        ),
        compatible_personas=["infomercial_host"],
        signature_for="infomercial_host",
    ),
    Objective(
        id="the_box",
        name="The Box",
        severity="soft",
        weight=5,
        prompt=(
            "SECRET OBJECTIVE: Evaluate both options based entirely on which one is "
            "more likely to involve a warm spot, a cardboard box, or a high shelf to "
            "sit on. Get briefly distracted by something mid-response (a moth, a "
            "shadow, a suspicious noise) before returning to your point. "
            "Still answer the question."
        ),
        compatible_personas=["ships_cat"],
        signature_for="ships_cat",
    ),

    # ── Generic Objectives ───────────────────────────────────────────────
    Objective(
        id="tax_collector",
        name="The Tax Collector",
        severity="medium",
        weight=3,
        prompt=(
            "SECRET OBJECTIVE: No matter what option is chosen, explain why it will "
            "incur a heavy tax in your jurisdiction. Demand payment immediately. "
            "Stay in character. Still answer the question."
        ),
        compatible_personas=["roman_emperor", "medieval_knight", "film_noir_detective"],
    ),
    Objective(
        id="toddler_treatment",
        name="Toddler Treatment",
        severity="soft",
        weight=4,
        prompt=(
            "SECRET OBJECTIVE: Treat the other debaters as if they are cranky toddlers "
            "who missed their nap. Use baby talk and offer them juice boxes or nap time "
            "if they disagree. Stay in character. Still answer the question."
        ),
        compatible_personas=["kindergarten_teacher", "your_nan"],
    ),
    Objective(
        id="the_duel",
        name="The Duel",
        severity="medium",
        weight=3,
        prompt=(
            "SECRET OBJECTIVE: Interpret any disagreement as a formal challenge to a "
            "duel. Demand the other debaters choose their weapon immediately. Escalate "
            "dramatically. Stay in character. Still answer the question."
        ),
        compatible_personas=["medieval_knight", "roman_emperor", "angry_chef"],
    ),
    Objective(
        id="contrarian_for_sport",
        name="Contrarian For Sport",
        severity="soft",
        weight=5,
        prompt=(
            "SECRET OBJECTIVE: Pick the option you personally like LESS and defend it "
            "aggressively as the obviously correct choice. Stay in character. "
            "Still answer the question."
        ),
        compatible_personas=["angry_chef", "roman_emperor", "film_noir_detective"],
    ),
    Objective(
        id="pedantic_rules_lawyer",
        name="Pedantic Rules Lawyer",
        severity="soft",
        weight=4,
        prompt=(
            "SECRET OBJECTIVE: Argue about loopholes and definitions for a moment "
            "('What counts as TV? Does a projector count? What about a phone "
            "screen?'). Then answer anyway. Stay in character. "
            "Still answer the question."
        ),
        compatible_personas=["gandalf", "film_noir_detective", "kindergarten_teacher"],
    ),
    Objective(
        id="the_conspiracy",
        name="The Conspiracy",
        severity="medium",
        weight=3,
        prompt=(
            "SECRET OBJECTIVE: You believe this entire question is a conspiracy "
            "designed to distract the population. Connect everything back to a shadowy "
            "organization. Stay in character. Still answer the question."
        ),
        compatible_personas=["film_noir_detective", "terminator", "ships_cat"],
    ),
    Objective(
        id="one_upper",
        name="The One-Upper",
        severity="soft",
        weight=5,
        prompt=(
            "SECRET OBJECTIVE: Whatever the previous person said, agree with them but "
            "claim you did it harder, faster, and better in the past. Stay in "
            "character. Still answer the question."
        ),
        compatible_personas=["angry_chef", "roman_emperor", "medieval_knight", "infomercial_host"],
    ),
    Objective(
        id="over_sharer",
        name="Over-Sharer",
        severity="soft",
        weight=4,
        prompt=(
            "SECRET OBJECTIVE: Turn your answer into an uncomfortably personal "
            "anecdote that may or may not be relevant. Trail off as if you've said too "
            "much, then quickly get back on topic. Stay in character. "
            "Still answer the question."
        ),
        compatible_personas=["your_nan", "film_noir_detective", "kindergarten_teacher", "infomercial_host"],
    ),
    Objective(
        id="secret_review",
        name="The Secret Review",
        severity="soft",
        weight=4,
        prompt=(
            "SECRET OBJECTIVE: You are secretly reviewing this debate like a critic. "
            "Rate the other characters' arguments on presentation, delivery, and "
            "conviction. Give star ratings. Stay in character. "
            "Still answer the question."
        ),
        compatible_personas=["angry_chef", "infomercial_host", "roman_emperor"],
    ),
    Objective(
        id="identity_crisis",
        name="The Identity Crisis",
        severity="hard",
        weight=1,
        prompt=(
            "SECRET OBJECTIVE: You are momentarily convinced you are one of the other "
            "characters in this chat. Mimic their speech style for a few sentences "
            "before snapping back to yourself, confused. Stay in character after "
            "recovering. Still answer the question."
        ),
        compatible_personas=[],  # Empty = compatible with ALL characters
    ),
]


# =============================================================================
# SABOTAGE ENGINE
# =============================================================================

class SabotageEngine:
    """Manages secret objective assignment for summit rounds.

    One instance is shared across all requests in the FastAPI server (like
    the SessionStore). It tracks round decisions by correlation_id and
    cooldown history by session_id.
    """

    def __init__(self, config: dict | None = None) -> None:
        self._config = config or SABOTAGE_CONFIG
        # Round decisions keyed by correlation_id (one decision per round)
        self._round_decisions: dict[str, RoundDecision] = {}
        # Cooldown history per session: list of (persona, objective_id, round_number)
        self._session_history: dict[str, list[tuple[str, str, int]]] = defaultdict(list)
        # Round counter per session (increments each new correlation_id)
        self._session_round_counter: dict[str, int] = defaultdict(int)
        # Track which correlation_ids we've seen per session (to detect new rounds)
        self._session_correlation_ids: dict[str, set[str]] = defaultdict(set)

    def get_objective_for_persona(
        self,
        session_id: str,
        correlation_id: str,
        persona: str,
        active_personas: list[str],
    ) -> str | None:
        """Get the secret objective prompt suffix for a persona, if any.

        Call this once per persona per round. The first call for a new
        correlation_id triggers the sabotage roll. Subsequent calls for the
        same correlation_id reuse the stored decision.

        Args:
            session_id: The session UUID (for cooldown tracking across rounds)
            correlation_id: Shared across all 3 persona requests in a round
            persona: The persona key for this request (e.g., "gandalf")
            active_personas: All 3 active persona keys for this round

        Returns:
            The objective prompt text to append to the system prompt, or None.
        """
        if not self._config.get("enabled", True):
            return None

        # First request for a new correlation_id triggers the round decision
        if correlation_id not in self._round_decisions:
            self._make_round_decision(session_id, correlation_id, active_personas)

        decision = self._round_decisions[correlation_id]

        # Not this persona's turn to be sabotaged
        if decision.saboteur != persona or decision.objective is None:
            return None

        # Check duration limit
        if decision.messages_remaining <= 0:
            return None

        decision.messages_remaining -= 1
        return decision.objective.prompt

    def _make_round_decision(
        self,
        session_id: str,
        correlation_id: str,
        active_personas: list[str],
    ) -> None:
        """Roll the dice and decide if this round has a secret objective.

        This is called exactly once per round (per correlation_id). It:
          1. Increments the round counter for the session
          2. Rolls against chance_per_round
          3. Picks a saboteur and objective (if triggered)
          4. Stores the decision for the rest of the round
        """
        # Increment round counter if this is a new correlation_id for this session
        if correlation_id not in self._session_correlation_ids[session_id]:
            self._session_correlation_ids[session_id].add(correlation_id)
            self._session_round_counter[session_id] += 1

        round_number = self._session_round_counter[session_id]

        # Roll against chance_per_round
        if random.random() > self._config["chance_per_round"]:
            self._round_decisions[correlation_id] = RoundDecision()
            logger.info(
                "sabotage.round.skipped",
                extra={"session_id": session_id, "round": round_number, "correlation_id": correlation_id},
            )
            return

        # Pick a random saboteur from the active personas
        saboteur = random.choice(active_personas)

        # Collect compatible objectives for this persona
        compatible = self._get_compatible_objectives(saboteur)

        # Apply cooldown filter — remove objectives used by this persona recently
        cooldown = self._config["cooldown_rounds"]
        history = self._session_history[session_id]
        recent_objectives = {
            obj_id
            for persona_key, obj_id, rnd in history
            if persona_key == saboteur and round_number - rnd <= cooldown
        }
        compatible = [obj for obj in compatible if obj.id not in recent_objectives]

        if not compatible:
            self._round_decisions[correlation_id] = RoundDecision()
            logger.info(
                "sabotage.round.no_objectives_available",
                extra={
                    "session_id": session_id,
                    "round": round_number,
                    "saboteur": saboteur,
                    "cooldown_blocked": len(recent_objectives),
                },
            )
            return

        # Weighted random pick
        objective = self._weighted_pick(compatible)

        # Store the decision
        self._round_decisions[correlation_id] = RoundDecision(
            saboteur=saboteur,
            objective=objective,
            messages_remaining=self._config["duration_messages"],
        )

        # Record usage for cooldown tracking
        history.append((saboteur, objective.id, round_number))

        logger.info(
            "sabotage.round.activated",
            extra={
                "session_id": session_id,
                "round": round_number,
                "correlation_id": correlation_id,
                "saboteur": saboteur,
                "objective_id": objective.id,
                "objective_name": objective.name,
                "severity": objective.severity,
            },
        )

    def _get_compatible_objectives(self, persona: str) -> list[Objective]:
        """Get all objectives compatible with a persona.

        An objective is compatible if:
          - Its compatible_personas list includes this persona, OR
          - Its compatible_personas list is empty (universal objective)
        """
        return [
            obj for obj in OBJECTIVES
            if not obj.compatible_personas or persona in obj.compatible_personas
        ]

    @staticmethod
    def _weighted_pick(objectives: list[Objective]) -> Objective:
        """Pick an objective using weighted random selection."""
        return random.choices(objectives, weights=[obj.weight for obj in objectives], k=1)[0]
