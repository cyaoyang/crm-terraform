import os
import json
import psycopg2
import psycopg2.extras

def handler(event, context):
    conn = None
    try:
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
            SELECT
                a.id AS account_id,
                c.id AS customer_id,
                c.name AS customer_name,
                a.product_type,
                a.loan_amount,
                a.amount_overdue,
                a.days_overdue,
                a.delinquency_stage
            FROM accounts a
            JOIN customers c ON c.id = a.customer_id
            ORDER BY a.days_overdue DESC
            LIMIT 50;
        """)
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
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)}),
        }
    finally:
        if conn:
            conn.close()