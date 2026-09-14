import os
import json
import psycopg2
import psycopg2.extras

def handler(event, context):
    conn = None
    try:
        customer_id = event.get("pathParameters", {}).get("customer_id")
        if not customer_id:
            return {"statusCode": 400, "body": json.dumps({"error": "customer_id required"})}

        conn = psycopg2.connect(
            host=os.environ["DB_HOST"],
            port=5432,
            dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            connect_timeout=5,
        )
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            SELECT id, name, phone, email, address, date_of_birth, national_id
            FROM customers WHERE id = %s;
        """, (customer_id,))
        customer = cur.fetchone()
        if customer is None:
            return {"statusCode": 404, "body": json.dumps({"error": "customer not found"})}

        cur.execute("""
            SELECT id AS account_id, product_type, loan_amount, amount_overdue,
                   days_overdue, delinquency_stage
            FROM accounts WHERE customer_id = %s
            ORDER BY days_overdue DESC;
        """, (customer_id,))
        accounts = cur.fetchall()

        cur.execute("""
            SELECT ce.id, ce.account_id, ce.event_type, ce.event_time, ce.summary
            FROM collection_events ce
            JOIN accounts a ON a.id = ce.account_id
            WHERE a.customer_id = %s
            ORDER BY ce.event_time DESC
            LIMIT 100;
        """, (customer_id,))
        events = cur.fetchall()

        def clean(rows):
            for row in rows:
                for key, value in row.items():
                    if hasattr(value, "__float__"):
                        row[key] = float(value)
            return rows

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "customer": clean([customer])[0],
                "accounts": clean(accounts),
                "events": clean(events),
            }, default=str),
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)}),
        }
    finally:
        if conn:
            conn.close()