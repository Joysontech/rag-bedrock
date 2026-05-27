import json
import logging

log = logging.getLogger()
log.setLevel(logging.INFO)


def handler(event, context):
    log.info("Ingest stub invoked. Event keys: %s", list(event.keys()))
    return {
        "statusCode": 200,
        "body": json.dumps({"status": "ok", "function": "ingest", "stub": True}),
    }
