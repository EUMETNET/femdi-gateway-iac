import asyncio
import os
import httpx
import uuid

# Configs
CLUSTERS = os.environ.get("CLUSTERS").split(",")
VAULT_TOKENS = os.environ.get("VAULT_TOKENS").split(",")
APISIX_API_KEYS = os.environ.get("APISIX_API_KEYS").split(",")
VAULT_BASE_PATH = "v1/apisix/consumers/test_users"
APISIX_SECRET_BASE_PATH = "$secret://vault/1/"
USER_GROUP = "TEST_USER"
DOMAIN_NAME = "meteogate.eu"
USER_COUNT = 10
BATCH_SIZE = 50
FILE_NAME = "test_users_apikeys.csv"
CONCURRENCY_LIMIT = 20  # Tune as needed

def random_key_for_user(length=16):
    # Use a UUID4, hex-encoded, and take the first 'length' chars for randomness
    base = uuid.uuid4().hex[:length]
    return f"test_key_{base}"


def get_users():
    return [(f"test_user_{i+1}", random_key_for_user()) for i in range(USER_COUNT)]


def save_to_all_vaults(client, users):
    return [save_to_vault(client, platform, u, k, VAULT_TOKENS[i]) for i, platform in enumerate(CLUSTERS) for u, k in users]


def delete_from_all_vaults(client, users):
    return [delete_from_vault(client, platform, u, VAULT_TOKENS[i]) for i, platform in enumerate(CLUSTERS) for u, _ in users]


def save_to_all_apisix(client, users):
    return [create_apisix_consumer(client, platform, u, APISIX_API_KEYS[i]) for i, platform in enumerate(CLUSTERS) for u, _ in users]


def delete_from_all_apisix(client, users):
    return [delete_apisix_consumer(client, platform, u, APISIX_API_KEYS[i]) for i, platform in enumerate(CLUSTERS) for u, _ in users]


def write_users_to_file(file_name, users):
    # Write usernames and API keys to a CSV file with header
    with open(file_name, "w") as f:
        f.write("username,apikey\n")
        for username, apikey in users:
            f.write(f"{username},{apikey}\n")
    print(f"Users and API keys written to path {file_name}")


def delete_users_file(file_name):
    if os.path.exists(file_name):
        os.remove(file_name)
        print(f"File {file_name} deleted.")
    else:
        print(f"Cannot delete users file {file_name} as it does not exist.")


async def save_to_vault(client, platform, username, apikey, token):
    url = f"https://vault.{platform}.{DOMAIN_NAME}/{VAULT_BASE_PATH}/{username}"
    headers = {"X-Vault-Token": token, "Content-Type": "application/json"}
    data = {"auth_key": apikey}
    r = await client.post(url, headers=headers, json=data)
    r.raise_for_status()


async def delete_from_vault(client, platform, username, token):
    url = f"https://vault.{platform}.{DOMAIN_NAME}/{VAULT_BASE_PATH}/{username}"
    headers = {"X-Vault-Token": token}
    r = await client.delete(url, headers=headers)
    if r.status_code not in (204, 200, 404):
        r.raise_for_status()


async def create_apisix_consumer(client, platform, username, apikey):
    url = f"https://admin-api.{platform}.{DOMAIN_NAME}/apisix/admin/consumers/{username}"
    headers = {"X-API-KEY": apikey, "Content-Type": "application/json"}
    consumer_data = {
        "username": username,
        "plugins": {
            "key-auth": {"key": f"{APISIX_SECRET_BASE_PATH}/test_users/{username}/auth_key"},
        },
        "group_id": USER_GROUP,
    }
    r = await client.put(url, headers=headers, json=consumer_data)
    r.raise_for_status()


async def delete_apisix_consumer(client, platform, username, apikey):
    full_url = f"https://admin-api.{platform}.{DOMAIN_NAME}/apisix/admin/consumers/{username}"
    headers = {"X-API-KEY": apikey}
    r = await client.delete(full_url, headers=headers)
    if r.status_code not in (204, 200, 404):
        r.raise_for_status()


async def run_with_semaphore(semaphore, coro):
    async with semaphore:
        return await coro


async def create_users():
    print(f"Creating {USER_COUNT} users and saving to clusters {(', ').join(CLUSTERS)}...")
    users = get_users()
    semaphore = asyncio.Semaphore(CONCURRENCY_LIMIT)
    async with httpx.AsyncClient() as client:
        for i in range(0, USER_COUNT, BATCH_SIZE):
            batch = users[i:i+BATCH_SIZE]
            vault_coros = save_to_all_vaults(client, batch)
            apisix_coros = save_to_all_apisix(client, batch)
            vault_tasks = [run_with_semaphore(semaphore, coro) for coro in vault_coros]
            apisix_tasks = [run_with_semaphore(semaphore, coro) for coro in apisix_coros]
            await asyncio.gather(*vault_tasks)
            await asyncio.gather(*apisix_tasks)
    print(f"{USER_COUNT} users created.")
    write_users_to_file(FILE_NAME, users)


async def delete_users():
    print(f"Deleting users from clusters {(', ').join(CLUSTERS)}...")
    users = get_users()
    semaphore = asyncio.Semaphore(CONCURRENCY_LIMIT)
    async with httpx.AsyncClient() as client:
        for i in range(0, USER_COUNT, BATCH_SIZE):
            batch = users[i:i+BATCH_SIZE]
            vault_coros = delete_from_all_vaults(client, batch)
            apisix_coros = delete_from_all_apisix(client, batch)
            vault_tasks = [run_with_semaphore(semaphore, coro) for coro in vault_coros]
            apisix_tasks = [run_with_semaphore(semaphore, coro) for coro in apisix_coros]
            await asyncio.gather(*vault_tasks)
            await asyncio.gather(*apisix_tasks)
    print(f"Users deleted.")
    delete_users_file(FILE_NAME)


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("Usage: python generate_test_users.py [create|delete]")
        sys.exit(1)
    op = sys.argv[1].lower()
    if op == "create":
        asyncio.run(create_users())
    elif op == "delete":
        asyncio.run(delete_users())
    else:
        print("Unknown operation. Use 'create' or 'delete'.")
        sys.exit(1)
