import json
import logging

log = logging.getLogger()
log.setLevel(logging.INFO)


def handler(event, context):
    log.info("Query stub invoked")
    body = json.loads(event.get("body") or "{}")
    return {
        "statusCode": 200,
        "body": json.dumps({
            "status": "ok",
            "function": "query",
            "stub": True,
            "received_question": body.get("question", ""),
        }),
    }
