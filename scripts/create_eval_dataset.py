#!/usr/bin/env python3
"""
Create a Bedrock Evaluation dataset from the Wisley RAG content.
Uploads a JSONL file to S3 in the format expected by Bedrock Model Evaluation.

Usage:
    python3 scripts/create_eval_dataset.py \
        --bucket rag-bedrock-docs-061051257340 \
        --region eu-west-2
"""
import argparse
import json
import os

import boto3

DATASET = [
    {
        "prompt": "When was RHS Garden Wisley established?",
        "referenceResponse": "RHS Garden Wisley was established in 1903 when Sir Thomas Hanbury gifted the site to the Royal Horticultural Society.",
        "category": "question_answering",
    },
    {
        "prompt": "How large is Wisley garden?",
        "referenceResponse": "Wisley has grown to over 240 acres from the original 60-acre site gifted in 1903.",
        "category": "question_answering",
    },
    {
        "prompt": "What opened at Wisley in 2021?",
        "referenceResponse": "The RHS opened the Hilltop building in 2021, dedicated to gardening science with laboratories and the National Plant Health Centre.",
        "category": "question_answering",
    },
    {
        "prompt": "How many plants does the Wisley Plant Centre sell?",
        "referenceResponse": "The Wisley Plant Centre offers over 9,000 plants for sale, all grown to RHS standards.",
        "category": "question_answering",
    },
    {
        "prompt": "What is the Wisley Glasshouse known for?",
        "referenceResponse": "The Wisley Glasshouse spans over 12,000 square metres and houses tropical, temperate, and dry zones.",
        "category": "question_answering",
    },
    {
        "prompt": "What horticultural styles does Wisley showcase?",
        "referenceResponse": "Wisley showcases styles including the formal Mediterranean Garden, wild flower meadows, and the Glasshouse.",
        "category": "question_answering",
    },
    {
        "prompt": "Who gifted the Wisley site to the RHS?",
        "referenceResponse": "The philanthropist Sir Thomas Hanbury gifted the 60-acre Wisley site to the Royal Horticultural Society.",
        "category": "question_answering",
    },
    {
        "prompt": "How many plant taxa does Wisley hold?",
        "referenceResponse": "The garden's plant collection includes over 30,000 different taxa.",
        "category": "question_answering",
    },
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--region", default="eu-west-2")
    parser.add_argument("--key", default="evals/wisley-eval-dataset.jsonl")
    args = parser.parse_args()

    lines = [json.dumps(record) for record in DATASET]
    content = "\n".join(lines)

    s3 = boto3.client("s3", region_name=args.region)
    s3.put_object(
        Bucket=args.bucket,
        Key=args.key,
        Body=content.encode("utf-8"),
        ContentType="application/jsonl",
    )

    s3_uri = f"s3://{args.bucket}/{args.key}"
    print(f"Uploaded {len(DATASET)} records to {s3_uri}")
    print(f"Use this S3 URI in Bedrock Evaluations: {s3_uri}")


if __name__ == "__main__":
    main()
