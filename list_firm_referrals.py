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
        if not law_firm_id:
            return {"statusCode": 403, "body": json.dumps({"error": "No law firm associated with this account"})}

        conn = psycopg2.connect(
            host=os.environ["DB_HOST"], port=5432, dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"], connect_timeout=5,
        )
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("""
            SELECT le.id, le.account_id, le.status, le.created_at, le.sent_at,
                   c.name AS customer_name, a.product_type, a.amount_overdue
            FROM legal_escalations le
            JOIN accounts a ON a.id = le.account_id
            JOIN customers c ON c.id = a.customer_id
            WHERE le.law_firm_id = %s
            ORDER BY le.created_at DESC;
        """, (law_firm_id,))
        rows = cur.fetchall()
        for row in rows:
            for key, value in row.items():
                if hasattr(value, "__float__"):
                    row[key] = float(value)
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(rows, default=str),
        }
    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
    finally:
        if conn:
            conn.close()