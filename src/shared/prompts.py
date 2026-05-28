"""Bedrock Prompt Management: fetch versioned prompts and render variables."""
import logging
from functools import lru_cache
from typing import Dict

import boto3

from shared.config import BEDROCK_REGION

log = logging.getLogger(__name__)

# Fallback prompt used when PROMPT_ARN is not set
_FALLBACK_TEMPLATE = """\
Context:
{{context}}

User question: {{question}}

Answer using only the context above. If the answer is not in the context, \
say "I don't have enough information to answer." \
Cite sources inline as [source-key]."""


@lru_cache(maxsize=8)
def _fetch_template(prompt_arn: str) -> str:
    """
    Fetch and cache the raw template string from Bedrock Prompt Management.
    Handles both TEXT and CHAT prompt types.
    The console chat builder creates CHAT type prompts (system + user messages).
    """
    log.info("Fetching prompt template: %s", prompt_arn)
    client = boto3.client("bedrock-agent", region_name=BEDROCK_REGION)

    parts      = prompt_arn.rsplit(":", 1)
    identifier = parts[0]
    version    = parts[1] if len(parts) == 2 else "1"

    response = client.get_prompt(
        promptIdentifier=identifier,
        promptVersion=version,
    )

    for variant in response.get("variants", []):
        cfg = variant.get("templateConfiguration", {})

        # TEXT type: simple template string
        if "text" in cfg:
            template = cfg["text"]["text"]
            log.info("Loaded TEXT prompt (%d chars)", len(template))
            return template

        # CHAT type: console builder stores messages as a list of content blocks
        if "chat" in cfg:
            messages   = cfg["chat"].get("messages", [])
            user_parts = []
            for msg in messages:
                if msg.get("role") == "user":
                    for block in msg.get("content", []):
                        text = block.get("text", "").strip()
                        if text:
                            user_parts.append(text)
            if user_parts:
                template = "\n".join(user_parts)
                log.info("Loaded CHAT prompt (%d chars)", len(template))
                return template

    raise ValueError(
        f"No usable template in prompt {prompt_arn}. "
        f"Types found: {[v.get('templateType') for v in response.get('variants', [])]}"
    )


def render_prompt(variables: Dict[str, str], prompt_arn: str = "") -> str:
    """
    Fetch the prompt template (or use the fallback) and substitute variables.
    Variables use {{double_braces}} syntax matching the Prompt Management UI.
    """
    template = _fetch_template(prompt_arn) if prompt_arn else _FALLBACK_TEMPLATE

    rendered = template
    for key, value in variables.items():
        rendered = rendered.replace("{{" + key + "}}", value or "")

    return rendered
