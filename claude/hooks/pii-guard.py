#!/usr/bin/env python3
"""PII Guard — PreToolUse hook that blocks personal information from being written.

Detects:
  - Email, phone (mobile/landline), My Number, credit card
  - API keys/tokens, private keys, DB connection strings, plaintext passwords
  - Japanese names (labeled), addresses (postal + prefecture), DOB (labeled)
  - Salary/compensation (labeled)
  - Passport, driver's license, health insurance, pension, residence card numbers
  - Corporate number (13 digits)
  - Bank account (branch + account), IBAN
  - Private IP addresses (10.x, 172.16-31.x, 192.168.x)
  - Combination PII: 3+ quasi-identifiers (company, dept, title, age, gender, etc.)

Exit codes:
  0 — no PII found (allow)
  2 — PII detected (BLOCK)
"""

import json
import os
import re
import sys
import time

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# File paths to skip (regex matched against file_path)
SKIP_PATHS = [
    r"pii[-_]guard[^/]*\.(py|sh)$",
    r"\.env\.example$",
    r"SKILL\.md$",
    r"/test[s_]?/.*\.(py|js|ts|rb|go)$",
]

# Email domains that are NOT real PII
SAFE_EMAIL_DOMAINS = {
    "example.com",
    "example.org",
    "example.net",
    "test.com",
    "test.org",
    "localhost",
    "placeholder.com",
    "users.noreply.github.com",
    "email.com",
}

SAFE_EMAIL_LOCALS = {"user", "foo", "bar", "test", "admin", "root", "nobody"}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def extract_text(tool: str, data: dict) -> tuple[str, str]:
    """Return (text_to_check, file_path_or_empty) for PreToolUse."""
    if tool == "Write":
        return data.get("content", ""), data.get("file_path", "")
    if tool == "Edit":
        return data.get("new_string", ""), data.get("file_path", "")
    if tool == "Bash":
        return data.get("command", ""), ""
    return "", ""


def should_skip_path(file_path: str) -> bool:
    if not file_path:
        return False
    return any(re.search(p, file_path) for p in SKIP_PATHS)


# ---------------------------------------------------------------------------
# PII Detection
# ---------------------------------------------------------------------------


def check_email(text: str) -> list[str]:
    matches = re.findall(
        r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}", text
    )
    real = []
    for m in matches:
        local, domain = m.rsplit("@", 1)
        if domain.lower() in SAFE_EMAIL_DOMAINS:
            continue
        if local.lower() in SAFE_EMAIL_LOCALS:
            continue
        # Skip if inside a regex pattern (preceded by common regex chars)
        idx = text.find(m)
        if idx > 0 and text[idx - 1] in r"[(\\":
            continue
        real.append(m)
    if real:
        masked = real[0][:3] + "***@" + real[0].split("@")[1]
        return [f"Email address ({masked})"]
    return []


def check_phone(text: str) -> list[str]:
    findings = []
    # Japanese mobile: 070/080/090 with separators
    if re.search(r"0[789]0[-\s]\d{4}[-\s]\d{4}", text):
        findings.append("Mobile phone number (0X0-XXXX-XXXX)")
    # Japanese mobile: 11 digits without separator
    elif re.search(r"\b0[789]0\d{8}\b", text):
        findings.append("Mobile phone number (0X0XXXXXXXX)")
    # Landline with hyphens — exclude mobile prefixes (070/080/090)
    for m in re.finditer(r"\b(0\d{1,4})-(\d{1,4})-(\d{4})\b", text):
        prefix = m.group(1)
        if re.match(r"^0[789]0$", prefix):
            continue  # already caught by mobile check
        if len(prefix) >= 2 and prefix != "00":
            findings.append("Landline phone number (0XX-XXXX-XXXX)")
            break
    return findings


def check_my_number(text: str) -> list[str]:
    """Japanese My Number (individual number): exactly 12 digits."""
    m = re.search(r"\b(\d{4})[-\s](\d{4})[-\s](\d{4})\b", text)
    if m:
        full = m.group(1) + m.group(2) + m.group(3)
        if len(full) == 12:
            # Exclude if part of a 16-digit credit card number
            start = m.start()
            end = m.end()
            before = text[max(0, start - 6) : start]
            after = text[end : end + 6]
            if not re.search(r"\d{4}[-\s]?$", before) and not re.search(
                r"^[-\s]?\d{4}", after
            ):
                return ["My Number pattern (12 digits)"]
    return []


def check_credit_card(text: str) -> list[str]:
    if re.search(r"\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b", text):
        return ["Credit card number pattern (16 digits)"]
    return []


def check_api_keys(text: str) -> list[str]:
    patterns = [
        (r"sk-[a-zA-Z0-9]{20,}", "OpenAI API key"),
        (r"ghp_[a-zA-Z0-9]{36}", "GitHub personal access token"),
        (r"gho_[a-zA-Z0-9]{36}", "GitHub OAuth token"),
        (r"ghs_[a-zA-Z0-9]{36}", "GitHub server token"),
        (r"AKIA[A-Z0-9]{16}", "AWS access key"),
        (r"xox[bpsar]-[\w\-]{10,}", "Slack token"),
        (r"-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----", "Private key"),
    ]
    findings = []
    for pat, label in patterns:
        if re.search(pat, text):
            findings.append(label)
    return findings


def check_credentials(text: str) -> list[str]:
    """DB connection strings, plaintext passwords."""
    findings = []
    # DB connection URIs with embedded credentials
    if re.search(
        r"(postgres|postgresql|mysql|mongodb|redis|amqp)"
        r"://[^:]+:[^@]+@[^\s]+",
        text,
    ):
        findings.append("DB connection string with credentials")
    # Plaintext passwords in config-like context
    pw_labels = (
        r"(?i)(password|passwd|pass|pwd|secret|token)"
        r"\s*[=:]\s*['\"]?[^\s'\"]{8,}"
    )
    match = re.search(pw_labels, text)
    if match:
        val = match.group(0)
        placeholders = [
            "xxx", "***", "your_", "change_me", "placeholder",
            "example", "dummy", "${", "ENV[", "os.environ",
            "process.env",
        ]
        if not any(p in val.lower() for p in placeholders):
            findings.append("Plaintext password/secret")
    return findings


def check_private_ip(text: str) -> list[str]:
    """Private/internal IP addresses (RFC 1918)."""
    safe_ips = {"127.0.0.1", "0.0.0.0", "10.0.0.1", "192.168.0.1", "192.168.1.1"}
    for m in re.finditer(
        r"\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3})\b"
        r"|\b(172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b"
        r"|\b(192\.168\.\d{1,3}\.\d{1,3})\b",
        text,
    ):
        ip = m.group(1) or m.group(2) or m.group(3)
        if ip in safe_ips:
            continue
        # Skip CIDR notation (e.g., 10.0.0.0/8)
        idx = m.end()
        if idx < len(text) and text[idx] == "/":
            continue
        return [f"Private IP address ({ip})"]
    return []


def check_bank_account(text: str) -> list[str]:
    """Bank branch code + account number, IBAN."""
    findings = []
    # Japanese bank: labeled context (branch code / account number)
    bank_labels = (
        r"(\u652f\u5e97(?:\u756a\u53f7|\u30b3\u30fc\u30c9)"  # shiten-bangou / shiten-code
        r"|\u53e3\u5ea7(?:\u756a\u53f7)?)"                    # kouza-bangou / kouza
    )
    if re.search(bank_labels + r"[\uff1a:\s]*\d{3,}", text):
        findings.append("Bank account number (labeled)")
    # IBAN: 2-letter country + 2 check digits + up to 30 alphanumeric
    if re.search(r"\b[A-Z]{2}\d{2}[A-Z0-9]{4,30}\b", text):
        # Require known country prefix to reduce false positives
        if re.search(
            r"\b(?:JP|US|GB|DE|FR|CH|AU|CA|SG|HK)\d{2}[A-Z0-9]{4,30}\b", text
        ):
            findings.append("IBAN")
    return findings


def check_id_documents(text: str) -> list[str]:
    """Passport, driver's license, health insurance, pension, residence card."""
    findings = []
    # Japanese passport: 2 alpha + 7 digits (e.g., TK1234567)
    m = re.search(r"\b[A-Z]{2}\d{7}\b", text)
    if m:
        idx = m.start()
        before = text[max(0, idx - 20) : idx]
        passport_labels = [
            "\u30d1\u30b9\u30dd\u30fc\u30c8",  # passport (JP)
            "passport",
            "\u65c5\u5238",                      # travel document (JP)
        ]
        if any(l in before.lower() for l in passport_labels):
            findings.append("Passport number")

    # Driver's license: 12 digits with label
    dl_labels = (
        r"(\u904b\u8ee2\u514d\u8a31"           # driver's license (JP)
        r"|\u514d\u8a31\u8a3c"                  # license certificate (JP)
        r"|driver'?s?\s*licen[sc]e)"
    )
    if re.search(dl_labels + r"[\uff1a:\s]*\w*\d{12}", text, re.I):
        findings.append("Driver's license number")

    # Health insurance card: labeled context
    hi_labels = (
        r"(\u4fdd\u967a\u8a3c"                  # insurance card (JP)
        r"|\u88ab\u4fdd\u967a\u8005"            # insured person (JP)
        r"|\u8a18\u53f7[\u30fb\u00b7]?\u756a\u53f7)"  # symbol/number (JP)
    )
    if re.search(hi_labels + r"[\uff1a:\s]*[\w\d\-]+", text):
        findings.append("Health insurance number")

    # Basic pension number: 4 digits - 6 digits with label
    pension_labels = (
        r"(\u5e74\u91d1\u756a\u53f7"            # pension number (JP)
        r"|\u57fa\u790e\u5e74\u91d1)"           # basic pension (JP)
    )
    if re.search(pension_labels + r"[\uff1a:\s]*\d{4}[-\s]?\d{6}", text):
        findings.append("Pension number")

    # Residence card: 2 alpha + 8 digits + 2 alpha with label
    rc_labels = (
        r"(\u5728\u7559\u30ab\u30fc\u30c9"     # residence card (JP)
        r"|\u5728\u7559\u8cc7\u683c"            # residence status (JP)
        r"|residence\s*card)"
    )
    if re.search(rc_labels + r"[\uff1a:\s]*[A-Z]{2}\d{8}[A-Z]{2}", text, re.I):
        findings.append("Residence card number")

    return findings


def check_corporate_number(text: str) -> list[str]:
    """Japanese corporate number: exactly 13 digits with label."""
    corp_labels = (
        r"(\u6cd5\u4eba\u756a\u53f7"            # corporate number (JP)
        r"|corporate\s*number)"
    )
    if re.search(corp_labels + r"[\uff1a:\s]*\d{13}\b", text, re.I):
        return ["Corporate number (13 digits)"]
    return []


def check_dob(text: str) -> list[str]:
    """Date of birth in labeled context."""
    dob_labels = (
        r"(\u751f\u5e74\u6708\u65e5"            # date of birth (JP)
        r"|\u8a95\u751f\u65e5"                   # birthday (JP)
        r"|date\s*of\s*birth|DOB)"
    )
    if re.search(
        dob_labels + r"[\uff1a:\s]*\d{4}[/\-\u5e74]\d{1,2}[/\-\u6708]\d{1,2}",
        text, re.I,
    ):
        return ["Date of birth (labeled)"]
    return []


def check_salary(text: str) -> list[str]:
    """Salary/compensation in labeled context."""
    salary_labels = (
        r"(\u5e74\u53ce|\u6708\u7d66|\u7d66\u4e0e|\u5831\u916c|\u8cde\u4e0e"  # annual income|monthly|salary|compensation|bonus (JP)
        r"|\u57fa\u672c\u7d66|\u624b\u53d6\u308a"                               # base pay|take-home (JP)
        r"|salary|compensation|annual\s*income)"
    )
    if re.search(
        salary_labels + r"[\uff1a:\s]*[\d,\uff10-\uff19]+\s*(\u5186|\u4e07\u5186)?",
        text, re.I,
    ):
        return ["Salary/compensation (labeled)"]
    return []


def check_quasi_identifier_combination(text: str) -> list[str]:
    """Detect combination PII: individually harmless quasi-identifiers that
    together can identify a person. Flags when 3+ distinct categories co-occur.
    """
    quasi_categories: list[tuple[str, list[str]]] = [
        (
            "company/org",
            [
                # company name, affiliation, employer, organization (JP)
                r"(?:\u4f1a\u793e\u540d|\u6240\u5c5e|\u52e4\u52d9\u5148|\u4f01\u696d\u540d"
                r"|\u7d44\u7e54)[\uff1a:\s]",
                r"(?:company|org(?:anization)?|employer)[\s:=]",
                # explicit company suffixes (JP: kabushiki-gaisha, etc.)
                r"\u682a\u5f0f\u4f1a\u793e|\uff08\u682a\uff09"
                r"|(?:Co\.|Ltd\.|Inc\.|Corp\.)",
            ],
        ),
        (
            "department",
            [
                # department, division, section, group, team (JP)
                r"(?:\u90e8\u7f72|\u90e8\u9580|\u8ab2|\u30b0\u30eb\u30fc\u30d7|\u30c1\u30fc\u30e0"
                r"|\u4fc2)[\uff1a:\s]",
                r"(?:department|division|team|unit|section)[\s:=]",
            ],
        ),
        (
            "job_title",
            [
                # job title, position, role (JP)
                r"(?:\u5f79\u8077|\u8077\u4f4d|\u8077\u7a2e|\u32a4\u30b8\u30b7\u30e7\u30f3"
                r"|\u808c\u66f8\u304d)[\uff1a:\s]",
                # specific JP titles: buchou, kachou, shunin, torishimariyaku, etc.
                r"(?:\u90e8\u9577|\u8ab2\u9577|\u4fc2\u9577|\u4e3b\u4efb|\u53d6\u7de0\u5f79"
                r"|\u793e\u9577|\u526f\u793e\u9577|\u5e38\u52d9|\u5c02\u52d9"
                r"|\u30de\u30cd\u30fc\u30b8\u30e3\u30fc|\u30ea\u30fc\u30c0\u30fc"
                r"|\u30c7\u30a3\u30ec\u30af\u30bf\u30fc)",
                r"(?:title|position|role)[\s:=]",
                r"(?:CEO|CTO|CFO|COO|VP|SVP|EVP|Director|Manager|Lead)\b",
            ],
        ),
        (
            "age",
            [
                # age (JP: nenrei, sai, sai)
                r"(?:\u5e74\u9f62|\u6b73|\u624d)[\uff1a:\s]*\d",
                r"\b(?:age)[\s:=]\s*\d",
                # NN years old (JP)
                r"\d{2}\u6b73",
            ],
        ),
        (
            "gender",
            [
                # gender (JP: seibetsu)
                r"(?:\u6027\u5225)[\uff1a:\s]",
                r"(?:gender|sex)[\s:=]",
                # gender with value: male/female/other (JP)
                r"(?:\u6027\u5225)[\uff1a:\s]*(?:\u7537|\u5973|\u305d\u306e\u4ed6"
                r"|male|female|other)",
            ],
        ),
        (
            "employee_id",
            [
                # employee number, staff ID (JP)
                r"(?:\u793e\u54e1\u756a\u53f7|\u5f93\u696d\u54e1\u756a\u53f7"
                r"|\u8077\u54e1\u756a\u53f7|\u30b9\u30bf\u30c3\u30d5ID"
                r"|employee[\s_]?(?:id|number|no))",
            ],
        ),
        (
            "username",
            [
                # username, account, login ID (JP)
                r"(?:\u30e6\u30fc\u30b6\u30fc\u540d|\u30a2\u30ab\u30a6\u30f3\u30c8"
                r"|\u30ed\u30b0\u30a4\u30f3ID)[\uff1a:\s]",
                r"(?:username|login|user[\s_]?id|account[\s_]?name)[\s:=]",
            ],
        ),
        (
            "hire_date",
            [
                # hire date, years of service (JP)
                r"(?:\u5165\u793e\u65e5|\u5165\u793e\u5e74\u6708|\u52e4\u7d9a\u5e74\u6570"
                r"|\u63a1\u7528\u65e5)[\uff1a:\s]",
                r"(?:hire[\s_]?date|start[\s_]?date|joined)[\s:=]",
            ],
        ),
        (
            "nationality",
            [
                # nationality, birthplace, country of origin (JP)
                r"(?:\u56fd\u7c4d|\u51fa\u8eab\u5730|\u51fa\u8eab\u56fd)[\uff1a:\s]",
                r"(?:nationality|citizenship|country[\s_]?of[\s_]?origin)[\s:=]",
            ],
        ),
        (
            "family",
            [
                # family structure, dependents, spouse, number of children (JP)
                r"(?:\u5bb6\u65cf\u69cb\u6210|\u6276\u990a\u5bb6\u65cf|\u914d\u5076\u8005"
                r"|\u5b50\u4f9b\u306e\u6570)[\uff1a:\s]",
                r"(?:dependents|spouse|marital[\s_]?status|family)[\s:=]",
            ],
        ),
    ]

    matched_categories: list[str] = []
    for cat_name, patterns in quasi_categories:
        for pat in patterns:
            if re.search(pat, text, re.I):
                matched_categories.append(cat_name)
                break  # one match per category is enough

    threshold = 3
    if len(matched_categories) >= threshold:
        cats = ", ".join(matched_categories[:5])
        return [
            f"Combination PII risk: {len(matched_categories)} quasi-identifiers "
            f"({cats})"
        ]
    return []


def check_postal_code(text: str) -> list[str]:
    # Postal mark prefix (JP)
    if re.search(r"\u3012\d{3}-?\d{4}", text):
        return ["Postal code (\u3012)"]
    # Without postal mark: match if not part of a phone number
    for m in re.finditer(r"(?<![0-9\-])(\d{3})-(\d{4})(?![0-9\-])", text):
        start = m.start()
        before = text[max(0, start - 6) : start]
        if re.search(r"\d+[-]$", before):
            continue  # part of a phone number
        return ["Postal code pattern (XXX-XXXX)"]
    return []


def check_japanese_address(text: str) -> list[str]:
    # JP prefectures: Tokyo-to, Hokkaido, Kyoto/Osaka-fu, XX-ken
    prefectures = (
        r"("
        r"\u6771\u4eac\u90fd|\u5317\u6d77\u9053"
        r"|(?:\u4eac\u90fd|\u5927\u962a)\u5e9c"
        r"|[\u4e00-\u9fff]{2,3}\u770c"
        r")"
    )
    # prefecture followed by city/ward/town/village/district
    if re.search(prefectures + r".{0,20}(\u5e02|\u533a|\u753a|\u6751|\u90e1)", text):
        return ["Japanese address (prefecture + city)"]
    return []


def check_japanese_name(text: str) -> list[str]:
    """Detect Japanese names when preceded by context labels."""
    # Labels: full name, name, contact, representative, applicant, etc. (JP)
    labels = (
        r"(\u6c0f\u540d|\u540d\u524d|\u62c5\u5f53\u8005?|\u9023\u7d61\u5148"
        r"|\u304a\u540d\u524d|\u30d5\u30eb\u30cd\u30fc\u30e0|\u672c\u540d"
        r"|\u8a18\u5165\u8005|\u7533\u8acb\u8005|\u4ee3\u8868\u8005)"
    )
    if re.search(
        labels + r"[\uff1a:]\s*[\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff]{2,}",
        text,
    ):
        return ["Japanese name (labeled context)"]
    return []


# ---------------------------------------------------------------------------
# Scan runner
# ---------------------------------------------------------------------------


def run_scan(text: str) -> list[str]:
    """Run all PII checks against text. Return list of findings."""
    findings: list[str] = []
    findings.extend(check_email(text))
    findings.extend(check_phone(text))
    findings.extend(check_my_number(text))
    findings.extend(check_credit_card(text))
    findings.extend(check_api_keys(text))
    findings.extend(check_credentials(text))
    findings.extend(check_postal_code(text))
    findings.extend(check_japanese_address(text))
    findings.extend(check_japanese_name(text))
    findings.extend(check_bank_account(text))
    findings.extend(check_id_documents(text))
    findings.extend(check_corporate_number(text))
    findings.extend(check_dob(text))
    findings.extend(check_salary(text))
    findings.extend(check_quasi_identifier_combination(text))
    return findings


LOG_PATH = os.environ.get("PII_GUARD_LOG") or os.path.expanduser(
    "~/.claude/pii-guard-log.jsonl"
)


def log_event(
    action: str, findings: list[str], tool: str, file_path: str
) -> None:
    """Append a JSONL record for false-positive tuning. Never raises.

    Records rule labels only — never the matched text itself.
    """
    try:
        findings = [f.split(" (")[0] for f in findings]  # labels only, no matched text
        rec = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "action": action,
            "tool": tool,
            "file_path": file_path,
            "findings": findings,
        }
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError:
        pass


def report(findings: list[str], context: str = "") -> int:
    """Print findings to stderr and return exit code."""
    if findings:
        detail = "; ".join(findings)
        prefix = f" [{context}]" if context else ""
        print(
            f"\u26a0\ufe0f PII Guard{prefix}: personal information detected"
            f" \u2014 {detail}",
            file=sys.stderr,
        )
        return 2
    return 0


def scan_and_report(text: str, tool: str, file_path: str = "") -> int:
    findings = run_scan(text)
    advisory = check_private_ip(text)
    if findings:
        log_event("block", findings + advisory, tool, file_path)
    elif advisory:
        log_event("advisory", advisory, tool, file_path)
    return report(findings, tool)


# ---------------------------------------------------------------------------
# Mode: PreToolUse (default) — scan tool input before execution
# ---------------------------------------------------------------------------


def read_hook_input() -> dict:
    """Claude Code passes hook input as JSON on stdin (not env vars).
    Shape: {"hook_event_name": "...", "tool_name": "...", "tool_input": {...}, ...}
    On unreadable/broken input return {} (fail-open: a guard failure must not
    block tool execution).
    """
    try:
        raw = sys.stdin.read()
    except OSError:
        return {}
    if not raw.strip():
        return {}
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return {}
    return data if isinstance(data, dict) else {}


def mode_pre_tool_use(payload: dict) -> int:
    tool = str(payload.get("tool_name", ""))
    data = payload.get("tool_input")
    if not isinstance(data, dict) or not data:
        return 0

    text, file_path = extract_text(tool, data)
    if not text:
        return 0
    if should_skip_path(file_path):
        return 0

    # For Bash: detect git commit and scan staged diff
    if tool == "Bash":
        cmd = data.get("command", "")
        if re.search(r"\bgit\s+commit\b", cmd):
            return mode_git_commit_scan()
        return scan_and_report(text, "Bash")

    return scan_and_report(text, tool, file_path)


# ---------------------------------------------------------------------------
# Mode: git commit scan — scan staged diff before commit
# ---------------------------------------------------------------------------


def mode_git_commit_scan() -> int:
    import subprocess

    try:
        result = subprocess.run(
            ["git", "diff", "--cached", "--no-color"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return 0
        diff_text = result.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return 0

    if not diff_text:
        return 0

    # Only scan added lines (lines starting with +, excluding +++ header)
    added_lines = []
    for line in diff_text.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            added_lines.append(line[1:])  # strip leading +

    if not added_lines:
        return 0

    text = "\n".join(added_lines)
    return scan_and_report(text, "git-commit")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    return mode_pre_tool_use(read_hook_input())


if __name__ == "__main__":
    sys.exit(main())
