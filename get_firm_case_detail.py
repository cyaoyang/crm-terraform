import os
import json
import psycopg2
import psycopg2.extras

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

        conn = psycopg2.connect(
            host=os.environ["DB_HOST"], port=5432, dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"], connect_timeout=5,
        )
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            SELECT le.id, le.account_id, le.status, le.escalation_type, le.created_at, le.sent_at, le.document_s3_key,
                   c.id AS customer_id, c.name, c.national_id, c.address, c.phone, c.email,
                   a.product_type, a.loan_amount, a.amount_overdue, a.days_overdue, a.delinquency_stage
            FROM legal_escalations le
            JOIN accounts a ON a.id = le.account_id
            JOIN customers c ON c.id = a.customer_id
            WHERE le.id = %s AND le.law_firm_id = %s;
        """, (escalation_id, law_firm_id))
        row = cur.fetchone()
        if row is None:
            return {"statusCode": 404, "body": json.dumps({"error": "case not found"})}

        for key, value in row.items():
            if hasattr(value, "__float__"):
                row[key] = float(value)

        cur.execute("""
            SELECT id, status, escalation_type, created_at, sent_at
            FROM legal_escalations
            WHERE account_id = %s AND law_firm_id = %s
            ORDER BY created_at DESC;
        """, (row["account_id"], law_firm_id))
        legal_history = cur.fetchall()
        for h in legal_history:
            for key, value in h.items():
                if hasattr(value, "__float__"):
                    h[key] = float(value)

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"case": row, "legal_history": legal_history}, default=str),
        }
    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
    finally:
        if conn:
            conn.close()