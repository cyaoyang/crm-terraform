import os
import json
import boto3
from botocore.client import Config
import psycopg2

s3 = boto3.client("s3", config=Config(signature_version="s3v4"), region_name="ap-southeast-1")

def handler(event, context):
    conn = None
    try:
        claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
        role = claims.get("custom:role")
        law_firm_id = claims.get("custom:law_firm_id")

        params = event.get("queryStringParameters") or {}
        escalation_id = params.get("escalation_id")
        doc_type = params.get("doc_type", "referral")

        if not escalation_id or role not in ("officer", "law_firm"):
            return {"statusCode": 400, "body": json.dumps({"error": "escalation_id required, must be officer or law_firm"})}

        conn = psycopg2.connect(
            host=os.environ["DB_HOST"], port=5432, dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"], connect_timeout=5,
        )
        cur = conn.cursor()

        cur.execute("""
            SELECT law_firm_id, document_s3_key, confirmation_document_s3_key
            FROM legal_escalations WHERE id = %s;
        """, (escalation_id,))
        row = cur.fetchone()
        if row is None:
            return {"statusCode": 404, "body": json.dumps({"error": "escalation not found"})}

        row_law_firm_id, document_key, confirmation_key = row

        if role == "law_firm" and str(row_law_firm_id) != law_firm_id:
            return {"statusCode": 404, "body": json.dumps({"error": "case not found"})}

        s3_key = document_key if doc_type == "referral" else confirmation_key
        if not s3_key:
            return {"statusCode": 404, "body": json.dumps({"error": f"no {doc_type} document available for this case"})}

        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": os.environ["LEGAL_DOCS_BUCKET"], "Key": s3_key},
            ExpiresIn=300,
        )

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"url": url}),
        }

    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
    finally:
        if conn:
            conn.close()