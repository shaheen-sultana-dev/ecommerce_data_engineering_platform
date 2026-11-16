import json
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

# Project directory
PROJECT_ROOT = Path(__file__).resolve().parents[1]

# API endpoint
API_URL = "https://dummyjson.com/products?limit=5"

# Bronze destination
BRONZE_DIR = PROJECT_ROOT / "data" / "bronze" / "api"


def ingest_api():

    # Create destination folder
    BRONZE_DIR.mkdir(parents=True, exist_ok=True)

    # Prepare HTTP request
    request = Request(
        API_URL,
        headers={"User-Agent": "EcommerceDataPipeline/1.0"}
    )

    try:
        # Send request and receive API response
        with urlopen(request, timeout=20) as response:
            data = json.loads(response.read().decode("utf-8"))

        # Validate API response
        if "products" not in data:
            raise ValueError("Unexpected API response format")

        # Save raw JSON response
        output_file = BRONZE_DIR / "products.json"

        with open(output_file, "w", encoding="utf-8") as file:
            json.dump(data, file, indent=4)

        print("API ingestion completed successfully!")
        print(f"Products received: {len(data['products'])}")
        print(f"Bronze file location: {output_file}")

    except HTTPError as error:
        print(f"HTTP error: {error.code} - {error.reason}")
        raise
        
    except URLError as error:
        print(f"Connection error: {error.reason}")
        raise
        
    except TimeoutError:
        print("API request timed out.")
        raise

if __name__ == "__main__":
    ingest_api()
