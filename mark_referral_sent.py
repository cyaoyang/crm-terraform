import os
import json
import base64
import boto3
import psycopg2
from datetime import datetime

s3 = boto3.client("s3")

def handler(event, context):
    conn = None
    try:
        claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
        if claims.get("custom:role") != "law_firm":
            return {"statusCode": 403, "body": json.dumps({"error": "Law firm access only"})}
        law_firm_id = claims.get("custom:law_firm_id")

        escalation_id = event.get("pathParameters", {}).get("escalation_id")
        if not escalation_id:
            return {"statusCode": 400, "body": json.dumps({"error": "escalation_id required"})}

        payload = json.loads(event["body"]) if isinstance(event.get("body"), str) else event
        document_base64 = payload.get("document_base64")

        conn = psycopg2.connect(
            host=os.environ["DB_HOST"], port=5432, dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"], connect_timeout=5,
        )
        cur = conn.cursor()

        cur.execute("SELECT account_id FROM legal_escalations WHERE id = %s AND law_firm_id = %s;",
                    (escalation_id, law_firm_id))
        row = cur.fetchone()
        if row is None:
            return {"statusCode": 404, "body": json.dumps({"error": "case not found"})}
        account_id = row[0]

        confirmation_s3_key = None
        if document_base64:
            confirmation_s3_key = f"legal-docs/{account_id}/confirmation_{int(datetime.utcnow().timestamp())}.pdf"
            s3.put_object(
                Bucket=os.environ["LEGAL_DOCS_BUCKET"], Key=confirmation_s3_key,
                Body=base64.b64decode(document_base64), ContentType="application/pdf",
                ServerSideEncryption="aws:kms", SSEKMSKeyId=os.environ["LEGAL_DOCS_KMS_KEY_ID"],
            )

        cur.execute("""
            UPDATE legal_escalations
            SET status = 'sent', sent_at = now(), confirmation_document_s3_key = COALESCE(%s, confirmation_document_s3_key)
            WHERE id = %s
            RETURNING sent_at;
        """, (confirmation_s3_key, escalation_id))
        sent_at = cur.fetchone()[0]

        conn.commit()
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"status": "sent", "sent_at": sent_at.isoformat()}),
        }
    except Exception as e:
        if conn:
            conn.rollback()
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
    finally:
        if conn:
            conn.close()