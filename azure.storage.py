

import sys
from azure.storage.blob import BlobServiceClient

ACCOUNT_NAME = ""
ACCOUNT_KEY  = ""
ACCOUNT_URL  = f""

def main():
    print(f"Connecting to storage account '{ACCOUNT_NAME}'...")

    try:
        client = BlobServiceClient(account_url=ACCOUNT_URL, credential=ACCOUNT_KEY)

        # Confirm connection by fetching account properties
        props = client.get_account_information()
        print(f"✅ Connected successfully!")
        print(f"   Account kind : {props.get('account_kind')}")
        print(f"   SKU name     : {props.get('sku_name')}")

        # List containers as further confirmation
        containers = list(client.list_containers())
        if containers:
            print(f"\n📦 Containers found ({len(containers)}):")
            for c in containers:
                print(f"   - {c['name']}")
        else:
            print("\n📦 No containers found (account is empty, but connection is valid).")

    except Exception as e:
        print(f"❌ Failed to connect: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
