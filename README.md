# e-automate AR MCP Server

A [Model Context Protocol](https://modelcontextprotocol.io) server that gives Claude read-only access to your e-automate (ECi) SQL database. Designed to support AR payment processing workflows — matching bank remittance data to customer accounts and invoices without requiring an e-automate API license.

---

## What It Does

When your AR team receives the bank's remittance export (CSV + check/stub images), they can ask Claude to:

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
- Read access to the e-automate SQL Server (Windows Auth or SQL login with `db_datareader`)
- **Claude Desktop** (any recent version)

---

## Installation

### One-liner (recommended)

```powershell
irm https://raw.githubusercontent.com/Allied-Business-Solutions/eautomate-ar-mcp/main/deploy/install.ps1 | iex
```

The installer will:
1. Verify Python 3.10+
2. Download and extract the server to `%LOCALAPPDATA%\Programs\eautomate-ar-mcp\`
3. Install Python dependencies
4. Prompt for SQL Server connection details and credentials
5. Register with Claude Desktop (`%APPDATA%\Claude\claude_desktop_config.json`)

Then **restart Claude Desktop**.

### Manual Install

1. Clone the repo and install dependencies:
   ```powershell
   git clone https://github.com/Allied-Business-Solutions/eautomate-ar-mcp.git
   cd eautomate-ar-mcp
   pip install -r requirements.txt
   ```

2. Copy `.env.example` to `.env` and fill in your values:
   ```
   EA_SERVER=your-sql-server
   EA_DATABASE=your-eautomate-db

   # SQL Server login — leave blank to use Windows Authentication
   EA_USERNAME=earead
   EA_PASSWORD=s3cr3t
   ```

3. Add to `%APPDATA%\Claude\claude_desktop_config.json`:
   ```json
   {
     "mcpServers": {
       "eautomate-ar": {
         "command": "python",
         "args": ["C:\\path\\to\\eautomate-ar-mcp\\server.py"],
         "env": {
           "EA_SERVER": "your-sql-server",
           "EA_DATABASE": "your-eautomate-db",
           "EA_USERNAME": "earead",
           "EA_PASSWORD": "s3cr3t"
         }
       }
     }
   }
   ```
   See `claude_desktop_config.example.json` for a complete example.

4. Restart Claude Desktop.

---

## Uninstall

Delete the `eautomate-ar` entry from `%APPDATA%\Claude\claude_desktop_config.json` and restart Claude Desktop.

To also remove the server files:
```powershell
Remove-Item "$env:LOCALAPPDATA\Programs\eautomate-ar-mcp" -Recurse -Force
```

---

## Usage Examples

Once installed, ask Claude naturally:

> "Check number 10482 came in for $314.50. It's from Riverside Medical Group — look them up and verify the invoice on the stub."

> "I have a $1,204.17 check from Cascade Auto Group covering two invoices: AR204851 and AR204852. Verify both."

> "Has check 28831 already been posted?"

> "Show me all open invoices for CustomerID 4521."

---

## Authentication

The server supports two authentication modes, selected automatically based on your `.env`:

| Mode | When used | How to configure |
|------|-----------|-----------------|
| **SQL Server login** | `EA_USERNAME` and `EA_PASSWORD` are set | Set both in `.env` or `claude_desktop_config` |
| **Windows Authentication** | `EA_USERNAME` is blank | Default — runs as the Windows account launching Claude |

**Recommended:** Create a dedicated SQL login with `db_datareader` permission only on the e-automate database. This scopes access tightly and works across machines without relying on Windows domain accounts.

```sql
-- Run on your SQL Server instance as sysadmin
CREATE LOGIN earead WITH PASSWORD = 'YourStrongPassword';
USE YourEautomateDatabase;
CREATE USER earead FOR LOGIN earead;
ALTER ROLE db_datareader ADD MEMBER earead;
```

---

## Related Projects

- [connectwise-manage-mcp](https://github.com/Allied-Business-Solutions/connectwise-manage-mcp) — MCP server for ConnectWise Manage
- [eautomate-ar-mcp](https://github.com/Allied-Business-Solutions/eautomate-ar-mcp) — this repo
