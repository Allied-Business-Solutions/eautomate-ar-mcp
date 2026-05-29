# e-automate AR MCP Server

A [Model Context Protocol](https://modelcontextprotocol.io) server that gives Claude read-only access to your e-automate (ECi) SQL database. Designed to support AR payment processing workflows — matching bank remittance data to customer accounts and invoices without requiring an e-automate API license.

Built for Allied Business Solutions.

---

## What It Does

When Tracy receives the bank's remittance export (CSV + check/stub images), she can ask Claude to:

- **Find a customer** by name or account number — even when the payer name on the check doesn't exactly match the e-automate customer name
- **Look up an invoice** and see its current balance
- **Verify a payment amount** against what's actually owed
- **Check for duplicate postings** before running the import
- **See all open invoices** for a customer when no invoice number is on the stub

Claude reads the check and stub images, extracts the invoice numbers and amounts, and uses these tools to confirm everything against the live database before any import is run.

---

## Tools

| Tool | Description |
|------|-------------|
| `search_customer` | Search by name or account number (partial match supported) |
| `get_invoice` | Look up an invoice by number — returns balance, customer, dates |
| `get_open_invoices` | All unpaid invoices for a customer, oldest first |
| `verify_payment_match` | Checks if a payment amount matches the invoice balance (exact/partial/over/already paid) |
| `check_duplicate_payment` | Searches receipt history by check number to prevent double-posting |
| `get_customer_summary` | Open invoice count, total balance, oldest date, unapplied credits |

All tools are **read-only** (`SELECT` queries only). No data is written, updated, or deleted.

---

## Prerequisites

- **Python 3.10+** — [python.org](https://www.python.org/downloads/)
- **Windows Authentication** access to the e-automate SQL Server
- The account running the server must have at least `db_datareader` on the e-automate database
- **Claude Code** or **Claude Desktop** (any recent version)

---

## Installation

### Quick Install (recommended)

```powershell
git clone https://github.com/Allied-Business-Solutions/eautomate-mcp.git
cd eautomate-mcp
.\deploy\install.ps1
```

The installer will:
1. Verify Python 3.10+
2. Install Python dependencies
3. Create a `.env` file from `.env.example`
4. Register the MCP server in the Claude config file

Then **restart Claude Desktop or Claude Code**.

By default the installer targets **Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`). Use `-Target` to change:

```powershell
# Claude Desktop (default)
.\deploy\install.ps1

# Claude Code only
.\deploy\install.ps1 -Target ClaudeCode

# Both
.\deploy\install.ps1 -Target Both
```

### SQL login or custom server

```powershell
# SQL Server login
.\deploy\install.ps1 -EAUsername earead -EAPassword "s3cr3t"

# Custom server + SQL login
.\deploy\install.ps1 -EAServer myserver -EADatabase MyDatabase -EAUsername earead -EAPassword "s3cr3t"
```

### Manual Install

1. Install dependencies:
   ```powershell
   pip install -r requirements.txt
   ```

2. Copy `.env.example` to `.env` and fill in your values:
   ```
   EA_SERVER=absapp4
   EA_DATABASE=CoAlliedBusiness

   # SQL Server login — leave blank to use Windows Authentication
   EA_USERNAME=earead
   EA_PASSWORD=s3cr3t
   ```

3. Add the server to `%USERPROFILE%\.claude\settings.json`:
   ```json
   {
     "mcpServers": {
       "eautomate": {
         "command": "python",
         "args": ["C:\\path\\to\\eautomate-mcp\\server.py"],
         "env": {
           "EA_SERVER": "absapp4",
           "EA_DATABASE": "CoAlliedBusiness",
           "EA_USERNAME": "earead",
           "EA_PASSWORD": "s3cr3t"
         }
       }
     }
   }
   ```
   See `claude_desktop_config.example.json` for a complete example.

4. Restart Claude.

---

## Uninstall

```powershell
# Claude Desktop (default)
.\deploy\uninstall.ps1

# Claude Code
.\deploy\uninstall.ps1 -Target ClaudeCode

# Both
.\deploy\uninstall.ps1 -Target Both
```

This removes the registration from the Claude config only. It does not uninstall Python packages or delete any files.

---

## Usage Examples

Once installed, ask Claude naturally:

> "Check number 23797 came in for $281.70. It's from American Biotech Labs — look them up and verify the invoice on the stub."

> "I have a $779.32 check from Larry H Miller Dealerships covering two invoices: AR601986 and AR601987. Verify both."

> "Has check 693361 already been posted?"

> "Show me all open invoices for CustomerID 1744."

---

## Authentication

The server supports two authentication modes, selected automatically based on your `.env`:

| Mode | When used | How to configure |
|------|-----------|-----------------|
| **SQL Server login** | `EA_USERNAME` and `EA_PASSWORD` are set | Set both in `.env` or `claude_desktop_config` |
| **Windows Authentication** | `EA_USERNAME` is blank | Default — runs as the Windows account launching Claude |

**Recommended:** Create a dedicated SQL login with `db_datareader` permission only on the e-automate database. This scopes access tightly and works across machines without relying on Windows domain accounts.

```sql
-- Run on absapp4 as sysadmin
CREATE LOGIN earead WITH PASSWORD = 'YourStrongPassword';
USE CoAlliedBusiness;
CREATE USER earead FOR LOGIN earead;
ALTER ROLE db_datareader ADD MEMBER earead;
```

---

## Related Projects

- [connectwise-manage-mcp](https://github.com/Allied-Business-Solutions/connectwise-manage-mcp) — MCP server for ConnectWise Manage
- [eautomate-ar-mcp](https://github.com/Allied-Business-Solutions/eautomate-ar-mcp) — this repo
