import csv
import json
import os
from pathlib import Path
from getpass import getpass

import psycopg2
from psycopg2.extras import Json


# --------------------------------------------------
# 1. PROJECT PATHS
# --------------------------------------------------

PROJECT_DIR = Path(__file__).resolve().parent.parent

postgres_folder = PROJECT_DIR / "data" / "bronze" / "postgres"
supplier_file = PROJECT_DIR / "data" / "bronze" / "csv" / "supplier_inventory.csv"
api_file = PROJECT_DIR / "data" / "bronze" / "api" / "products.json"
stream_folder = PROJECT_DIR / "data" / "bronze" / "streaming"


# --------------------------------------------------
# 2. DATABASE CONNECTION
# --------------------------------------------------

password = os.getenv("PGPASSWORD") or getpass(
    "Enter PostgreSQL password: "
)

conn = psycopg2.connect(
    host="localhost",
    port=5433,
    database="ecommerce_demo",
    user="postgres",
    password=password
)


# --------------------------------------------------
# 3. CSV LOADING HELPER
# --------------------------------------------------

def load_csv_table(cur, file_path, table_name, columns):

    if not file_path.exists():
        raise FileNotFoundError(f"File not found: {file_path}")

    records = []

    with open(file_path, "r", newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)

        if not reader.fieldnames:
            raise ValueError(f"CSV has no header: {file_path}")

        missing_columns = set(columns) - set(reader.fieldnames)

        if missing_columns:
            raise ValueError(
                f"Missing columns in {file_path.name}: {missing_columns}"
            )

        for row in reader:
            # Empty CSV fields are represented as SQL NULL
            values = tuple(
                row[column] if row[column] != "" else None
                for column in columns
            )
            records.append(values)

    placeholders = ", ".join(["%s"] * len(columns))
    column_names = ", ".join(columns)

    query = f"""
        INSERT INTO {table_name} ({column_names})
        VALUES ({placeholders})
    """

    cur.executemany(query, records)

    print(f"{table_name}: {len(records)} records loaded")


# --------------------------------------------------
# 4. LOAD ALL DATA
# --------------------------------------------------

try:

    with conn:
        with conn.cursor() as cur:

            # Clear previous demo records before reloading
            cur.execute("""
                TRUNCATE TABLE
                    staging.customers_raw,
                    staging.products_raw,
                    staging.orders_raw,
                    staging.order_items_raw,
                    staging.supplier_inventory_raw,
                    staging.api_products_raw,
                    staging.order_events_raw
            """)

            # PostgreSQL Bronze CSV files

            load_csv_table(
                cur,
                postgres_folder / "customers.csv",
                "staging.customers_raw",
                [
                    "customer_id", "customer_name", "email",
                    "city", "state", "created_at"
                ]
            )

            load_csv_table(
                cur,
                postgres_folder / "products.csv",
                "staging.products_raw",
                [
                    "product_id", "product_name", "category",
                    "unit_price", "updated_at"
                ]
            )

            load_csv_table(
                cur,
                postgres_folder / "orders.csv",
                "staging.orders_raw",
                [
                    "order_id", "customer_id", "order_ts",
                    "order_status", "payment_method"
                ]
            )

            load_csv_table(
                cur,
                postgres_folder / "order_items.csv",
                "staging.order_items_raw",
                [
                    "order_item_id", "order_id", "product_id",
                    "quantity", "unit_price", "discount_amount"
                ]
            )

            # Supplier CSV Bronze file

            load_csv_table(
                cur,
                supplier_file,
                "staging.supplier_inventory_raw",
                [
                    "supplier_id", "product_id", "supplier_name",
                    "available_quantity", "unit_cost", "last_updated"
                ]
            )

            # External API Bronze JSON file

            if not api_file.exists():
                raise FileNotFoundError(f"API file not found: {api_file}")

            with open(api_file, "r", encoding="utf-8") as file:
                api_data = json.load(file)

            cur.execute(
                """
                INSERT INTO staging.api_products_raw
                    (raw_payload, source_url)
                VALUES (%s, %s)
                """,
                (
                    Json(api_data),
                    "https://dummyjson.com/products?limit=5"
                )
            )

            print("staging.api_products_raw: 1 JSON document loaded")

            # Streaming Bronze JSONL batch files

            batch_files = sorted(
                stream_folder.glob("event_batch_*.jsonl")
            )

            if not batch_files:
                raise FileNotFoundError(
                    "No streaming event batch files found"
                )

            event_count = 0

            for batch_file in batch_files:

                event_records = []

                with open(batch_file, "r", encoding="utf-8") as file:

                    for line in file:

                        if not line.strip():
                            continue

                        event = json.loads(line)

                        event_records.append((
                            event.get("event_id"),
                            event.get("event_type"),
                            event.get("order_id"),
                            event.get("customer_id"),
                            str(event["amount"])
                            if event.get("amount") is not None else None,
                            event.get("event_timestamp"),
                            batch_file.name
                        ))

                cur.executemany(
                    """
                    INSERT INTO staging.order_events_raw
                        (event_id, event_type, order_id, customer_id,
                         amount, event_timestamp, source_file)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    """,
                    event_records
                )

                event_count += len(event_records)

            print(
                f"staging.order_events_raw: "
                f"{event_count} events loaded"
            )

    print("\nAll seven datasets loaded successfully!")

except Exception as error:
    print("\nStaging load failed:", error)
    raise

finally:
    conn.close()