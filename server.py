"""
e-automate MCP Server
Provides read-only tools for querying the e-automate SQL database.
Used by Claude sessions and n8n payment processing workflows.
"""

import os
import pyodbc
from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP

load_dotenv()

EA_SERVER   = os.getenv("EA_SERVER",   "absapp4")
EA_DATABASE = os.getenv("EA_DATABASE", "CoAlliedBusiness")
EA_USERNAME = os.getenv("EA_USERNAME", "")
EA_PASSWORD = os.getenv("EA_PASSWORD", "")

if EA_USERNAME and EA_PASSWORD:
    CONN_STR = (
        f"Driver={{SQL Server}};"
        f"Server={EA_SERVER};"
        f"Database={EA_DATABASE};"
        f"UID={EA_USERNAME};"
        f"PWD={EA_PASSWORD};"
    )
else:
    CONN_STR = (
        f"Driver={{SQL Server}};"
        f"Server={EA_SERVER};"
        f"Database={EA_DATABASE};"
        f"Trusted_Connection=yes;"
    )

mcp = FastMCP("eautomate-ar", dependencies=["pyodbc", "python-dotenv"])


def _conn():
    return pyodbc.connect(CONN_STR, timeout=15)


def _rows(cur):
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


# ---------------------------------------------------------------------------
# Tool: search_customer
# ---------------------------------------------------------------------------

@mcp.tool()
def search_customer(query: str) -> list[dict]:
    """
    Search for an e-automate customer by name or account number (CustomerNumber).
    Returns up to 20 active matches including CustomerID, CustomerNumber,
    CustomerName, City, State, open balance, and unapplied credits.

    Use this to match a payer name from a check or remittance stub to the
    correct e-automate customer account before looking up invoices.

    Args:
        query: Partial or full customer name or account number
               e.g. "American Biotech", "AB00-TBS", "Larry Miller"
    """
    like = f"%{query}%"
    with _conn() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT TOP 20
                CustomerID,
                CustomerNumber,
                CustomerName,
                City,
                State,
                Active,
                Invoices   AS OpenInvoicesBalance,
                Unapplied  AS UnappliedCredits,
                Hold
            FROM ARCustomers
            WHERE Active = 1
              AND (CustomerName LIKE ? OR CustomerNumber LIKE ?)
            ORDER BY CustomerName
        """, like, like)
        results = _rows(cur)
    if not results:
        return [{"message": f"No active customers found matching '{query}'"}]
    return results


# ---------------------------------------------------------------------------
# Tool: get_invoice
# ---------------------------------------------------------------------------

@mcp.tool()
def get_invoice(invoice_number: str) -> dict:
    """
    Look up a specific AR invoice by its invoice number (e.g. "AR601961").
    Returns invoice details including customer, total, amount due, due date,
    description, PO number, and void status.

    Args:
        invoice_number: The e-automate invoice number, e.g. "AR601961"
    """
    with _conn() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                i.InvoiceID,
                i.InvoiceNumber,
                i.Date           AS InvoiceDate,
                i.DueDate,
                i.Total,
                i.Due            AS BalanceDue,
                i.Void,
                i.Description,
                i.PONumber,
                i.CustomerID,
                c.CustomerNumber,
                c.CustomerName,
                c.City,
                c.State
            FROM ARInvoices i
            JOIN ARCustomers c ON i.CustomerID = c.CustomerID
            WHERE i.InvoiceNumber = ?
        """, invoice_number)
        rows = _rows(cur)
    if not rows:
        return {"error": f"Invoice '{invoice_number}' not found"}
    return rows[0]


# ---------------------------------------------------------------------------
# Tool: get_open_invoices
# ---------------------------------------------------------------------------

@mcp.tool()
def get_open_invoices(customer_id: int) -> list[dict]:
    """
    Return all open (unpaid or partially paid) AR invoices for a customer,
    ordered oldest first. Use this to see what a customer owes when there
    is no invoice number on the remittance stub.

    Args:
        customer_id: The integer CustomerID from ARCustomers
                     (obtained from search_customer)
    """
    with _conn() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                i.InvoiceNumber,
                i.Date           AS InvoiceDate,
                i.DueDate,
                i.Total,
                i.Due            AS BalanceDue,
                i.Description,
                i.PONumber,
                CASE WHEN i.DueDate < GETDATE() THEN 'PAST DUE' ELSE 'Current' END AS Status
            FROM ARInvoices i
            WHERE i.CustomerID = ?
              AND i.Due > 0
              AND i.Void = 0
            ORDER BY i.Date ASC
        """, customer_id)
        results = _rows(cur)
    if not results:
        return [{"message": f"No open invoices for CustomerID {customer_id}"}]
    return results


# ---------------------------------------------------------------------------
# Tool: verify_payment_match
# ---------------------------------------------------------------------------

@mcp.tool()
def verify_payment_match(invoice_number: str, payment_amount: float) -> dict:
    """
    Check whether a payment amount matches what is owed on a specific invoice.
    Returns the invoice balance and a clear MatchStatus indicating whether
    this is an exact match, partial payment, overpayment, or already paid.

    Args:
        invoice_number: e.g. "AR601961"
        payment_amount: Dollar amount from the check or remittance stub
    """
    inv = get_invoice(invoice_number)
    if "error" in inv:
        return inv

    balance = float(inv["BalanceDue"])
    diff = round(payment_amount - balance, 2)

    result = {
        "InvoiceNumber":  inv["InvoiceNumber"],
        "CustomerName":   inv["CustomerName"],
        "CustomerNumber": inv["CustomerNumber"],
        "InvoiceTotal":   inv["Total"],
        "BalanceDue":     balance,
        "PaymentAmount":  payment_amount,
        "Difference":     diff,
        "Void":           inv["Void"],
    }

    if inv["Void"]:
        result["MatchStatus"] = "ERROR - Invoice is VOIDED"
    elif balance == 0:
        result["MatchStatus"] = "WARNING - Invoice already paid in full"
    elif diff == 0:
        result["MatchStatus"] = "EXACT MATCH"
    elif diff < 0:
        result["MatchStatus"] = f"PARTIAL PAYMENT - ${abs(diff):.2f} will remain on invoice"
    else:
        result["MatchStatus"] = f"OVERPAYMENT - ${diff:.2f} would become unapplied credit"

    return result


# ---------------------------------------------------------------------------
# Tool: check_duplicate_payment
# ---------------------------------------------------------------------------

@mcp.tool()
def check_duplicate_payment(check_number: str, customer_name_hint: str = "") -> list[dict]:
    """
    Check whether a check number has already been posted in e-automate.
    Searches receipt history by check number to prevent duplicate postings.
    Returns prior posting details if found, or a safe-to-post confirmation.

    Args:
        check_number: Check number from the bank file, e.g. "23797"
        customer_name_hint: Optional partial customer name to narrow results
    """
    like_customer = f"%{customer_name_hint}%" if customer_name_hint else "%"
    with _conn() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT TOP 10
                HReceiptNumber,
                CustomerName,
                Date,
                Amount,
                CheckNumber,
                CheckDate,
                Description,
                BranchName
            FROM ARHReceipts
            WHERE CheckNumber = ?
              AND CustomerName LIKE ?
            ORDER BY Date DESC
        """, check_number, like_customer)
        results = _rows(cur)
    if not results:
        return [{"message": f"No prior posting found for check #{check_number} — safe to post"}]
    return results


# ---------------------------------------------------------------------------
# Tool: get_customer_summary
# ---------------------------------------------------------------------------

@mcp.tool()
def get_customer_summary(customer_id: int) -> dict:
    """
    Return a full AR summary for a customer: open invoice count, total open
    balance, oldest invoice date, latest due date, and unapplied credits.
    Useful for understanding a customer's overall account health before posting.

    Args:
        customer_id: The integer CustomerID from ARCustomers
    """
    with _conn() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                COUNT(*)       AS OpenInvoiceCount,
                SUM(i.Due)     AS TotalOpenBalance,
                MIN(i.Date)    AS OldestInvoiceDate,
                MAX(i.DueDate) AS LatestDueDate
            FROM ARInvoices i
            WHERE i.CustomerID = ?
              AND i.Due > 0
              AND i.Void = 0
        """, customer_id)
        inv_row = _rows(cur)[0]

        cur.execute("""
            SELECT CustomerNumber, CustomerName, Unapplied, Hold
            FROM ARCustomers
            WHERE CustomerID = ?
        """, customer_id)
        cust_row = _rows(cur)

    if not cust_row:
        return {"error": f"CustomerID {customer_id} not found"}
    return {**cust_row[0], **inv_row}


if __name__ == "__main__":
    mcp.run(transport="stdio")
