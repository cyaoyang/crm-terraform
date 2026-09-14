import os
import json
import psycopg2

def handler(event, context):
    conn = None
    try:
        if isinstance(event.get("body"), str):
            payload = json.loads(event["body"])
        else:
            payload = event

        account_id = payload.get("account_id")
        officer_id = payload.get("officer_id")
        successful = payload.get("successful")
        duration_seconds = payload.get("duration_seconds")
        notes = payload.get("notes", "")

        if not account_id or not officer_id or successful is None:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "account_id, officer_id, and successful are required"}),
            }

        if successful and duration_seconds is None:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "duration_seconds is required when successful is true"}),
            }

        conn = psycopg2.connect(
            host=os.environ["DB_HOST"],
            port=5432,
            dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            connect_timeout=5,
        )
        cur = conn.cursor()

        cur.execute("SELECT 1 FROM accounts WHERE id = %s", (account_id,))
        if cur.fetchone() is None:
            return {"statusCode": 404, "body": json.dumps({"error": "account_id not found"})}

        cur.execute("SELECT 1 FROM collection_officers WHERE id = %s", (officer_id,))
        if cur.fetchone() is None:
            return {"statusCode": 404, "body": json.dumps({"error": "officer_id not found"})}

        cur.execute(
            """
            INSERT INTO collection_calls (account_id, officer_id, successful, duration_seconds, notes)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id, call_time;
            """,
            (account_id, officer_id, successful, duration_seconds if successful else None, notes),
        )
        new_id, call_time = cur.fetchone()
        conn.commit()

        return {
            "statusCode": 201,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"id": str(new_id), "call_time": call_time.isoformat()}),
        }

    except Exception as e:
        if conn:
            conn.rollback()
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)}),
        }
    finally:
        if conn:
            conn.close()