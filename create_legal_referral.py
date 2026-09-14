import os
import json
import io
import boto3
import psycopg2
from datetime import datetime
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

s3 = boto3.client("s3")

def generate_referral_pdf(customer, account, law_firm, officer):
    buffer = io.BytesIO()
    c = canvas.Canvas(buffer, pagesize=A4)
    width, height = A4
    y = height - 30 * mm

    c.setFont("Helvetica-Bold", 14)
    c.drawString(25 * mm, y, "Joe Bank - Legal Referral Case Summary")
    y -= 12 * mm

    c.setFont("Helvetica", 10)
    c.drawString(25 * mm, y, f"Date: {datetime.utcnow().strftime('%d %B %Y')}")
    y -= 6 * mm
    c.drawString(25 * mm, y, f"Referred by: {officer['name']} (Joe Bank Collections)")
    y -= 6 * mm
    c.drawString(25 * mm, y, f"Referred to: {law_firm['name']}")
    y -= 12 * mm

    c.setFont("Helvetica-Bold", 11)
    c.drawString(25 * mm, y, "Customer Details")
    y -= 7 * mm
    c.setFont("Helvetica", 10)
    for label, value in [
        ("Name", customer["name"]), ("NRIC", customer["national_id"]),
        ("Address", customer["address"]), ("Phone", customer["phone"]),
        ("Email", customer["email"]),
    ]:
        c.drawString(25 * mm, y, f"{label}: {value}")
        y -= 6 * mm

    y -= 6 * mm
    c.setFont("Helvetica-Bold", 11)
    c.drawString(25 * mm, y, "Account Details")
    y -= 7 * mm
    c.setFont("Helvetica", 10)
    for label, value in [
        ("Product", account["product_type"].replace("_", " ").title()),
        ("Loan amount", f"${account['loan_amount']:,.2f}"),
        ("Amount overdue", f"${account['amount_overdue']:,.2f}"),
        ("Days overdue", str(account["days_overdue"])),
        ("Delinquency stage", account["delinquency_stage"].replace("_", " ").title()),
    ]:
        c.drawString(25 * mm, y, f"{label}: {value}")
        y -= 6 * mm

    c.showPage()
    c.save()
    buffer.seek(0)
    return buffer.read()


def handler(event, context):
    conn = None
    try:
        print("STEP: checking claims")
        claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
        if claims.get("custom:role") != "officer":
            return {"statusCode": 403, "body": json.dumps({"error": "Only officers can create legal referrals"})}

        payload = json.loads(event["body"]) if isinstance(event.get("body"), str) else event
        account_id = payload.get("account_id")
        officer_id = payload.get("officer_id")
        law_firm_id = payload.get("law_firm_id")
        escalation_type = payload.get("escalation_type", "letter_of_demand")

        if not account_id or not officer_id or not law_firm_id:
            return {"statusCode": 400, "body": json.dumps({"error": "account_id, officer_id, law_firm_id required"})}

        print("STEP: connecting to DB")
        conn = psycopg2.connect(
            host=os.environ["DB_HOST"], port=5432, dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"], connect_timeout=5,
        )
        cur = conn.cursor()
        print("STEP: DB connected, running account query")

        cur.execute("""
            SELECT c.name, c.national_id, c.address, c.phone, c.email,
                   a.product_type, a.loan_amount, a.amount_overdue, a.days_overdue, a.delinquency_stage
            FROM accounts a JOIN customers c ON c.id = a.customer_id
            WHERE a.id = %s;
        """, (account_id,))
        row = cur.fetchone()
        if row is None:
            return {"statusCode": 404, "body": json.dumps({"error": "account not found"})}
        customer = {"name": row[0], "national_id": row[1], "address": row[2], "phone": row[3], "email": row[4]}
        account = {"product_type": row[5], "loan_amount": float(row[6]), "amount_overdue": float(row[7]),
                   "days_overdue": row[8], "delinquency_stage": row[9]}
        print("STEP: account query done, running law firm query")

        cur.execute("SELECT name FROM law_firms WHERE id = %s;", (law_firm_id,))
        firm_row = cur.fetchone()
        if firm_row is None:
            return {"statusCode": 404, "body": json.dumps({"error": "law_firm not found"})}
        law_firm = {"name": firm_row[0]}
        print("STEP: law firm query done, running officer query")

        cur.execute("SELECT name FROM collection_officers WHERE id = %s;", (officer_id,))
        officer_row = cur.fetchone()
        if officer_row is None:
            return {"statusCode": 404, "body": json.dumps({"error": "officer not found"})}
        officer = {"name": officer_row[0]}
        print("STEP: officer query done, generating PDF")

        pdf_bytes = generate_referral_pdf(customer, account, law_firm, officer)
        print(f"STEP: PDF generated, {len(pdf_bytes)} bytes, uploading to S3")

        s3_key = f"legal-docs/{account_id}/referral_{int(datetime.utcnow().timestamp())}.pdf"
        s3.put_object(
            Bucket=os.environ["LEGAL_DOCS_BUCKET"], Key=s3_key, Body=pdf_bytes,
            ContentType="application/pdf", ServerSideEncryption="aws:kms",
            SSEKMSKeyId=os.environ["LEGAL_DOCS_KMS_KEY_ID"],
        )
        print("STEP: S3 upload done, inserting escalation row")

        cur.execute("""
            INSERT INTO legal_escalations (account_id, officer_id, law_firm_id, escalation_type, document_s3_key, status)
            VALUES (%s, %s, %s, %s, %s, 'drafted')
            RETURNING id, created_at;
        """, (account_id, officer_id, law_firm_id, escalation_type, s3_key))
        new_id, created_at = cur.fetchone()
        print("STEP: escalation inserted, updating account stage")

        cur.execute("UPDATE accounts SET delinquency_stage = 'legal_escalation' WHERE id = %s;", (account_id,))
        cur.execute("INSERT INTO delinquency_events (account_id, stage) VALUES (%s, 'legal_escalation');", (account_id,))

        conn.commit()
        print("STEP: done, committing")
        return {
            "statusCode": 201,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"id": str(new_id), "created_at": created_at.isoformat()}),
        }

    except Exception as e:
        print(f"STEP: EXCEPTION - {e}")
        if conn:
            conn.rollback()
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
    finally:
        if conn:
            conn.close()