import random
import uuid
from datetime import datetime, timedelta
from faker import Faker

fake = Faker()
random.seed(42)

NUM_CUSTOMERS = 30

PRODUCT_TYPES = ["credit_card", "cash_advance", "personal_loan", "property_loan"]

STAGE_WEIGHTS = {
    "current":            0.35,
    "special_mention":    0.25,
    "substandard":        0.15,
    "doubtful":           0.10,
    "loss":               0.05,
    "legal_escalation":   0.06,
    "resolved":           0.04,
}

STAGE_ORDER = ["current", "special_mention", "substandard", "doubtful", "loss", "legal_escalation"]
STAGE_DAYS = {
    "current": 0, "special_mention": 30, "substandard": 90,
    "doubtful": 120, "loss": 180, "legal_escalation": 130,
}

LAW_FIRMS = [
    ("Rajah & Tann Singapore LLP", "collections@rajahtannsg.example.com", "+65 6535 3600"),
    ("Drew & Napier LLC", "collections@drewnapier.example.com", "+65 6535 0733"),
    ("WongPartnership LLP", "collections@wongpartnership.example.com", "+65 6416 8000"),
]

OFFICERS = [
    ("Wei Ming Tan", "EMP1001"),
    ("Siti Nurhaliza Rahman", "EMP1002"),
    ("Kumar Selvaraj", "EMP1003"),
    ("Jasmine Lim Hui Ling", "EMP1004"),
]

CALL_NOTES_SUCCESS = [
    "Customer acknowledged overdue amount, promised payment by end of week.",
    "Discussed hardship situation, customer requested payment plan.",
    "Customer disputed the overdue amount, escalated for account review.",
    "Customer confirmed payment already made, requesting confirmation of receipt.",
]

def sg_address():
    block = random.randint(1, 999)
    street = fake.street_name()
    unit_floor = random.randint(1, 20)
    unit_num = random.randint(1, 300)
    postal = random.randint(100000, 829999)
    return f"Blk {block} {street}, #{unit_floor:02d}-{unit_num:02d}, Singapore {postal:06d}"

def generate_nric():
    prefix = random.choice(["S", "T"])
    suffix = random.choice("ABCDEFGHJKLMNPQRSTUVWXYZ")
    return f"{prefix}XXXXXXX{suffix}"

def esc(s):
    return s.replace("'", "''")

def weighted_stage():
    stages = list(STAGE_WEIGHTS.keys())
    weights = list(STAGE_WEIGHTS.values())
    return random.choices(stages, weights=weights, k=1)[0]

sql_lines = []
sql_lines.append("-- Auto-generated fake seed data. Safe to publish/demo.")
sql_lines.append("BEGIN;\n")

law_firm_ids = []
sql_lines.append("-- Law firms")
for name, email, phone in LAW_FIRMS:
    fid = str(uuid.uuid4())
    law_firm_ids.append(fid)
    sql_lines.append(
        f"INSERT INTO law_firms (id, name, email, phone) VALUES "
        f"('{fid}', '{esc(name)}', '{esc(email)}', '{esc(phone)}');"
    )

officer_ids = []
sql_lines.append("\n-- Collection officers")
for name, emp_id in OFFICERS:
    oid = str(uuid.uuid4())
    officer_ids.append(oid)
    email = f"{emp_id.lower()}@bank.example.com"
    sql_lines.append(
        f"INSERT INTO collection_officers (id, name, employee_id, email) VALUES "
        f"('{oid}', '{esc(name)}', '{esc(emp_id)}', '{esc(email)}');"
    )

sql_lines.append("\n-- Customers, accounts, and their history")
now = datetime.utcnow()

for _ in range(NUM_CUSTOMERS):
    cust_id = str(uuid.uuid4())
    name = fake.name()
    phone = f"+65 {random.randint(8,9)}{random.randint(100,999)} {random.randint(1000,9999)}"
    email = fake.email()
    address = sg_address()
    dob = fake.date_of_birth(minimum_age=21, maximum_age=70).strftime("%d/%m/%Y")
    nric = generate_nric()

    sql_lines.append(
        f"INSERT INTO customers (id, name, phone, email, address, date_of_birth, national_id) VALUES "
        f"('{cust_id}', '{esc(name)}', '{esc(phone)}', '{esc(email)}', '{esc(address)}', "
        f"'{dob}', '{nric}');"
    )

    num_accounts = random.choices([1, 2, 3], weights=[0.6, 0.3, 0.1])[0]
    for _ in range(num_accounts):
        acct_id = str(uuid.uuid4())
        product = random.choice(PRODUCT_TYPES)
        stage = weighted_stage()
        loan_amount = round(random.uniform(2000, 80000), 2)

        if stage == "resolved":
            amount_overdue = 0
            days_overdue = 0
        else:
            amount_overdue = round(loan_amount * random.uniform(0.05, 0.6), 2)
            days_overdue = STAGE_DAYS.get(stage, 0)

        sql_lines.append(
            f"INSERT INTO accounts (id, customer_id, product_type, loan_amount, amount_overdue, "
            f"days_overdue, delinquency_stage) VALUES "
            f"('{acct_id}', '{cust_id}', '{product}', {loan_amount}, {amount_overdue}, "
            f"{days_overdue}, '{stage}');"
        )

        if stage == "resolved":
            path = ["current", "special_mention", "resolved"]
        else:
            end_idx = STAGE_ORDER.index(stage) if stage in STAGE_ORDER else 0
            path = STAGE_ORDER[: end_idx + 1]

        event_time = now - timedelta(days=STAGE_DAYS.get(stage, 0) + random.randint(1, 5))
        for step_stage in path:
            sql_lines.append(
                f"INSERT INTO delinquency_events (account_id, stage, entered_at) VALUES "
                f"('{acct_id}', '{step_stage}', '{event_time.isoformat()}');"
            )
            event_time += timedelta(days=random.randint(5, 20))

        if stage in ("special_mention", "substandard", "doubtful", "loss"):
            template = f"reminder_{stage}"
            sent_at = now - timedelta(days=random.randint(0, 3))
            sql_lines.append(
                f"INSERT INTO communications (account_id, channel, template_used, status, sent_at) "
                f"VALUES ('{acct_id}', 'email', '{template}', 'sent', '{sent_at.isoformat()}');"
            )

        if stage not in ("current", "resolved") and random.random() < 0.4:
            officer_id = random.choice(officer_ids)
            successful = random.random() < 0.6
            call_time = now - timedelta(days=random.randint(0, 5))
            duration = random.randint(60, 900) if successful else "NULL"
            notes = esc(random.choice(CALL_NOTES_SUCCESS)) if successful else "No answer, will retry."
            sql_lines.append(
                f"INSERT INTO collection_calls (account_id, officer_id, call_time, successful, "
                f"duration_seconds, notes) VALUES "
                f"('{acct_id}', '{officer_id}', '{call_time.isoformat()}', {str(successful).upper()}, "
                f"{duration}, '{notes}');"
            )

        if stage == "legal_escalation":
            officer_id = random.choice(officer_ids)
            law_firm_id = random.choice(law_firm_ids)
            sent_at = now - timedelta(days=random.randint(0, 2))
            s3_key = f"legal-docs/{acct_id}/letter_of_demand.pdf"
            sql_lines.append(
                f"INSERT INTO legal_escalations (account_id, officer_id, law_firm_id, "
                f"escalation_type, document_s3_key, status, sent_at) VALUES "
                f"('{acct_id}', '{officer_id}', '{law_firm_id}', 'letter_of_demand', "
                f"'{s3_key}', 'sent', '{sent_at.isoformat()}');"
            )

sql_lines.append("\nCOMMIT;")

with open("seed_data.sql", "w", encoding="utf-8") as f:
    f.write("\n".join(sql_lines))

print(f"Generated seed_data.sql with {NUM_CUSTOMERS} customers.")