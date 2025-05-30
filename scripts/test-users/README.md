# How to Run the Test User Generation Script

This project provides a Python script and shell script to generate and clean up test users in Vault and APISIX.

- Tested with macOS and Python 3.13

## Setup

1. **Create a virtual environment (recommended):**

   The shell script will automatically create a venv in `scripts/test-users/venv` if it does not exist.

2. **Install dependencies:**

   The shell script will install dependencies from `scripts/test-users/requirements.txt` automatically.

3. **Set required environment variables:**
   - `CLUSTERS` (e.g. eumetsat,ecmwf)
   - `VAULT_TOKENS` (your Vault tokens in the same order as clusters)
   - `APISIX_API_KEYS` (your APISIX admin keys in the same order as clusters and vault tokens)

   Example:
   ```zsh
   export CLUSTERS="eumetsat,ecmwf"
   export VAULT_TOKENS="hvs.xxxxx,hvs.yyyyy"
   export APISIX_API_KEYS="key-xxxx,key-yyyy"
   ```

4. **Run the script:**

   From the `scripts/test-users` directory, use the shell script to create or delete users:
   ```zsh
   ./manage_users.sh create
   ./manage_users.sh delete
   ```

---

**Notes:**
- The test users and corresponding API keys are written to `test_users_apikeys.csv` file.
