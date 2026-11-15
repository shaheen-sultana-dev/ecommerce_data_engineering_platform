import csv
import getpass
from pathlib import Path

import psycopg2

# Project directory
PROJECT_DIR = Path(__file__).resolve().parents[1]

# Bronze storage directory
BRONZE_DIR = PROJECT_DIR / "data" / "bronze" / "postgres"

# Tables to extract
TABLES = [
    "customers",
    "products",
    "orders",
    "order_items"
]

def extract_data():
    BRONZE_DIR.mkdir(parents=True, exist_ok=True)
    password = getpass.getpass("Enter PostgreSQL password: ")
    
    # Connect to PostgreSQL
    connection = psycopg2.connect(
        host="localhost",
        port="5433",
        database="ecommerce_demo",
        user="postgres",
        password=password
    )

    print("Connected to PostgreSQL!")

    try:
        for table in TABLES:
            query=f'SELECT * FROM source."{table}" ORDER BY 1'
            with connection.cursor() as cursor:
                cursor.execute(query)
                columns=[desc[0] for desc in cursor.description]
                rows=cursor.fetchall()
            output_file = BRONZE_DIR / f"{table}.csv"
            with open(output_file, "w", newline="", encoding="utf-8") as file:
                writer = csv.writer(file)
                writer.writerow(columns)
                writer.writerows(rows)
            print(f"{table}: {len(rows)} records extracted")
        print("\nPostgreSQL ingestion completed!")
    finally:
        connection.close()

if __name__ == "__main__":
    extract_data()                    