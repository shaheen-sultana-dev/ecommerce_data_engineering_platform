import json
from pathlib import Path

# Project directory
PROJECT_ROOT = Path(__file__).resolve().parents[1]

# Source event file
SOURCE_FILE = (
    PROJECT_ROOT / "data" / "source_files" / "order_events.jsonl"
)

# Bronze destination
BRONZE_DIR = PROJECT_ROOT / "data" / "bronze" / "streaming"

# Number of events in each micro-batch
BATCH_SIZE = 2


def ingest_stream():

    if not SOURCE_FILE.exists():
        raise FileNotFoundError(f"File not found: {SOURCE_FILE}")

    BRONZE_DIR.mkdir(parents=True, exist_ok=True)

    batch = []
    batch_number = 1
    total_events = 0

    with open(SOURCE_FILE, "r", encoding="utf-8") as file:

        for line_number, line in enumerate(file, start=1):

            if not line.strip():
                continue

            try:
                event = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(
                    f"Invalid JSON on line {line_number}"
                ) from error

            batch.append(event)
            total_events += 1

            # Write a batch when it reaches the batch size
            if len(batch) == BATCH_SIZE:

                output_file = (
                    BRONZE_DIR / f"event_batch_{batch_number:03d}.jsonl"
                )

                with open(output_file, "w", encoding="utf-8") as output:
                    for record in batch:
                        output.write(json.dumps(record) + "\n")

                print(f"Batch {batch_number} saved: {len(batch)} events")

                batch = []
                batch_number += 1

    # Save any remaining events
    if batch:

        output_file = (
            BRONZE_DIR / f"event_batch_{batch_number:03d}.jsonl"
        )

        with open(output_file, "w", encoding="utf-8") as output:
            for record in batch:
                output.write(json.dumps(record) + "\n")

        print(f"Batch {batch_number} saved: {len(batch)} events")

    print("\nStreaming simulation completed!")
    print(f"Total events processed: {total_events}")


if __name__ == "__main__":
    ingest_stream()