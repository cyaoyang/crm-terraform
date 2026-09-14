import os
import json
import psycopg2
import psycopg2.extras

def handler(event, context):
    conn = None
    try:
        conn = psycopg2.connect(
            host=os.environ["DB_HOST"], port=5432, dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"], connect_timeout=5,
        )
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("SELECT id, name FROM law_firms ORDER BY name;")
        rows = cur.fetchall()
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