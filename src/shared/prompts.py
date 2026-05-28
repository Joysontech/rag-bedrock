"""Bedrock Prompt Management: fetch versioned prompts and render variables."""
import logging
from functools import lru_cache
from typing import Dict

import boto3

from shared.config import BEDROCK_REGION

log = logging.getLogger(__name__)

# Fallback prompt used when PROMPT_ARN is not set (dev/test convenience)
_FALLBACK_TEMPLATE = """\
Context:
{{context}}
{{history}}
User question: {{question}}

Answer using only the context above. If the answer is not in the context, \
say "I don't have enough information to answer." \
Cite sources inline as [source-key]."""


@lru_cache(maxsize=8)
def _fetch_template(prompt_arn: str) -> str:
    """
    Fetch and cache the raw template string from Bedrock Prompt Management.
    Cached per ARN so warm Lambda invocations skip the API call.
    The ARN should include the version suffix (:1, :2, etc.) so the cache
    key changes when you deploy a new version.
    """
    log.info("Fetching prompt template from Prompt Management: %s", prompt_arn)
    client = boto3.client("bedrock-agent", region_name=BEDROCK_REGION)

    # Split arn:...:prompt/ID:VERSION into identifier and version
    parts = prompt_arn.rsplit(":", 1)
    identifier = parts[0]
    version    = parts[1] if len(parts) == 2 else "1"

    response = client.get_prompt(
        promptIdentifier=identifier,
        promptVersion=version,
    )

    # Find the TEXT variant (there may be others for different modalities)
    for variant in response.get("variants", []):
        cfg = variant.get("templateConfiguration", {})
        if "text" in cfg:
            template = cfg["text"]["text"]
            log.info("Loaded prompt template (%d chars)", len(template))
            return template

    raise ValueError(f"No text variant found in prompt {prompt_arn}")


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
