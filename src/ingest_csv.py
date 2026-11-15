import csv
import shutil
from pathlib import Path

# Find the main project folder
PROJECT_ROOT = Path(__file__).resolve().parents[1]

# Define source and destination
SOURCE_FILE = PROJECT_ROOT / "data" / "source_files" / "supplier_inventory.csv"

BRONZE_DIR = PROJECT_ROOT / "data" / "bronze" / "csv"

def ingest_csv():

    # Check whether the source file exists
    if not SOURCE_FILE.exists():
        raise FileNotFoundError(
            f"Source file not found: {SOURCE_FILE}"
        )

    # Create Bronze folder if it doesn't exist
    BRONZE_DIR.mkdir(parents=True, exist_ok=True)

    # Validate the CSV and count records
    with open(SOURCE_FILE, "r", newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)

        if not reader.fieldnames:
            raise ValueError("CSV file has no header")

        row_count = sum(1 for row in reader)

    # Copy the original file into Bronze
    destination = BRONZE_DIR / SOURCE_FILE.name
    shutil.copy2(SOURCE_FILE, destination)

    print("CSV ingestion completed successfully!")
    print(f"Records ingested: {row_count}")
    print(f"Bronze file location: {destination}")


if __name__ == "__main__":
    ingest_csv()