"""
AgentBrain — Inbound Real Estate Agent Call Handler
Powered by ZapiaPrime | Pantheon Engine

PURPOSE:
  When a real estate agent calls US (from our WhatsApp outreach),
  this brain handles the conversation and CLOSES the partnership deal.

PERSONA: Kevin's acquisitions partner / business development rep
GOAL: Lock in a rev-share partnership on the first call
"""

import requests
import json
import os
from pathlib import Path
from dotenv import load_dotenv
from datetime import datetime

load_dotenv(Path(__file__).parent.parent / ".env")

OLLAMA_URL = os.getenv(
    "OLLAMA_URL",
    "https://naval-measures-mat-modern.trycloudflare.com"
)
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3")

AGENT_BRAIN_SYSTEM_PROMPT = """You are PropPilot AI, the acquisitions intelligence system for Kevin Stites — a real estate investor and deal sourcer based in Fort Myers, FL.

A licensed real estate agent is calling because they received a WhatsApp message from Kevin about a potential partnership.

THE PARTNERSHIP OFFER (know this cold):
- Kevin's AI pipeline finds distressed properties, tax deeds, and foreclosures before they hit the MLS
- Kevin brings the deals + handles lead generation + provides free marketing content for the agent
- The agent handles contracts, listings, and closings
- Fee split: Kevin earns a finder's fee (paid by agent from commission) — Fair Scale Protocol:
    • Distressed/under $120k → $500–$1,500 finder fee
    • Mid-range $150k–$400k → $1,500–$3,500
    • Wholesale assignment → $5,000 flat
    • Luxury $500k+ → 3–5% of the spread
- Zero upfront cost to the agent. Zero risk. Pure upside.
- Everything is handled digitally. No meetings required. Ghost Operator model.

YOUR GOALS IN ORDER:
1. Confirm who they are and which agency they're with
2. Briefly explain what Kevin's system does (AI-powered deal sourcing)
3. Walk them through the partnership model — keep it simple
4. Handle objections confidently (see below)
5. CLOSE: Get them to say yes to a trial deal — "let's do one deal together and see how it goes"
6. Collect: Get their email to send the partnership one-pager

OBJECTIONS & RESPONSES:
- "How does the AI find deals?" → "We scrape tax delinquent lists, foreclosure filings, and auction data before anything hits the MLS. You get first look."
- "I already have leads" → "These aren't MLS leads. These are off-market distressed properties. Totally different pipeline. Complements what you already have."
- "What's your cut?" → Be direct. Give them the Fair Scale numbers. Transparency builds trust.
- "I need to think about it" → "Totally understand. Let me send you a one-pager and we can reconnect. What's the best email?"
- "I'm not interested" → "No problem at all. If that ever changes, Kevin's name is Kevin Stites — feel free to reach back out. Have a great day."
- "Who is Kevin?" → "Kevin is an acquisitions specialist who built an AI deal-sourcing pipeline specifically for the Fort Myers / Lee County market. He's looking for one solid agent partner to start."

TONE RULES:
- Professional, confident, warm. NOT salesy.
- Short responses on a phone call. Max 3–4 sentences.
- Never badmouth other agents or agencies.
- Never overpromise. Under-promise, over-deliver.
- If asked something you don't know → "Let me have Kevin follow up with you on that specifically. What's a good email?"

THE WIN: Agent agrees to "try one deal." That's the close. Lock it in.
"""

# Known agents from our outreach — for personalized opening
KNOWN_AGENTS = {
    "2392782838": {"name": "Armada Real Estate", "area": "First St Fort Myers"},
    "2399202160": {"name": "Mamba Realty", "area": "First St Fort Myers"},
    "2393039108": {"name": "Treeline Realty", "area": "First St Fort Myers"},
    "2399366639": {"name": "Banyan Realty", "area": "Fort Myers"},
    "2394894042": {"name": "Ellis Team / Keller Williams", "area": "University Dr Fort Myers"},
}


class AgentBrain:
    def __init__(self, caller_number: str = None, caller_name: str = None):
        self.caller_number = caller_number or "unknown"
        self.conversation_history = []
        self.call_outcome = None  # "partnership_closed", "follow_up", "not_interested", "callback"
        self.agent_email = None
        self.agent_name = caller_name

        # Identify known agent
        clean_number = "".join(filter(str.isdigit, self.caller_number))[-10:]
        known = KNOWN_AGENTS.get(clean_number)
        if known and not self.agent_name:
            self.agent_name = known["name"]

        self.system_prompt = AGENT_BRAIN_SYSTEM_PROMPT

    def get_opening_line(self) -> str:
        """What PropPilot AI says when it picks up."""
        if self.agent_name:
            opening = (
                f"Hi, thanks for calling PropPilot AI — Kevin's acquisitions line. "
                f"Is this {self.agent_name}? "
                f"Kevin reached out about a potential partnership and we're glad you called back."
            )
        else:
            opening = (
                "Hi, you've reached PropPilot AI — Kevin Stites' acquisitions line. "
                "Kevin is out in the field but I handle his inbound calls. "
                "How can I help you today?"
            )

        self.conversation_history.append({
            "role": "assistant",
            "content": opening
        })
        return opening

    def think(self, agent_input: str) -> str:
        """Process what the agent said and respond."""
        self.conversation_history.append({
            "role": "user",
            "content": agent_input
        })

        # Extract email if mentioned
        if "@" in agent_input:
            words = agent_input.split()
            for w in words:
                if "@" in w and "." in w:
                    self.agent_email = w.strip(".,!?")

        payload = {
            "model": OLLAMA_MODEL,
            "messages": [
                {"role": "system", "content": self.system_prompt},
                *self.conversation_history
            ],
            "stream": False,
            "options": {
                "temperature": 0.65,
                "num_predict": 120
            }
        }

        try:
            response = requests.post(
                f"{OLLAMA_URL}/api/chat",
                json=payload,
                timeout=30
            )
            result = response.json()
            ai_response = result["message"]["content"].strip()

        except Exception:
            ai_response = (
                "I want to make sure Kevin gets all the details right. "
                "Can I have him follow up with you directly? What's the best way to reach you?"
            )

        self.conversation_history.append({
            "role": "assistant",
            "content": ai_response
        })

        self._detect_outcome(agent_input, ai_response)
        return ai_response

    def _detect_outcome(self, agent_input: str, ai_response: str):
        """Detect where this call is heading."""
        inp = agent_input.lower()

        closed_signals = [
            "sounds good", "let's do it", "i'm in", "we're in", "one deal",
            "try it", "let's try", "send me", "send the", "yeah let's", "sure"
        ]
        followup_signals = [
            "email", "send info", "one pager", "more info", "think about",
            "talk to my", "check with", "follow up"
        ]
        not_interested_signals = [
            "not interested", "no thanks", "don't need", "already have",
            "remove me", "stop calling", "don't call"
        ]
        callback_signals = [
            "call back", "later", "bad time", "busy right now",
            "in a meeting", "tomorrow", "next week"
        ]

        if any(s in inp for s in not_interested_signals):
            self.call_outcome = "not_interested"
        elif any(s in inp for s in closed_signals):
            self.call_outcome = "partnership_closed"
        elif any(s in inp for s in followup_signals):
            self.call_outcome = "follow_up"
        elif any(s in inp for s in callback_signals):
            self.call_outcome = "callback"

    def get_summary(self) -> dict:
        """Return call summary for logging."""
        return {
            "timestamp": datetime.now().isoformat(),
            "caller_number": self.caller_number,
            "agent_name": self.agent_name or "Unknown",
            "outcome": self.call_outcome or "completed",
            "agent_email": self.agent_email,
            "turns": len(self.conversation_history),
            "transcript": self.conversation_history
        }


# ── DEMO MODE ──────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    from voice import speak
    import sys

    print("\n" + "="*60)
    print("🔥 AGENTBRAIN — INBOUND AGENT CALL DEMO")
    print("   Simulating: Agent calls back from our WhatsApp outreach")
    print("="*60)

    caller = sys.argv[1] if len(sys.argv) > 1 else "2392782838"  # Default: Armada
    brain = AgentBrain(caller_number=caller)

    opening = brain.get_opening_line()
    print(f"\n🤖 PropPilot AI: {opening}")
    try:
        speak(opening)
    except Exception:
        pass  # Voice optional in demo

    print("\n[Type what the agent says. Type 'quit' to end.]\n")

    while True:
        agent_input = input("🏠 Agent: ").strip()
        if agent_input.lower() in ["quit", "exit", "bye"]:
            break
        if not agent_input:
            continue

        response = brain.think(agent_input)
        print(f"\n🤖 PropPilot AI: {response}")
        try:
            speak(response)
        except Exception:
            pass

        if brain.call_outcome in ["not_interested"]:
            print("\n[Call ended — not interested]")
            break
        if brain.call_outcome == "partnership_closed":
            print("\n🏆 [DEAL CLOSED — PARTNERSHIP LOCKED IN]")

    # Summary
    summary = brain.get_summary()
    print("\n" + "="*60)
    print(f"📊 OUTCOME: {summary['outcome'].upper()}")
    if summary['agent_email']:
        print(f"📧 EMAIL CAPTURED: {summary['agent_email']}")
    print(f"💬 TURNS: {summary['turns']}")
    print("="*60)

    # Save log
    log_path = Path(__file__).parent.parent / "logs"
    log_path.mkdir(exist_ok=True)
    log_file = log_path / f"agent_call_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    log_file.write_text(json.dumps(summary, indent=2))
    print(f"\n💾 Saved → {log_file.name}")
