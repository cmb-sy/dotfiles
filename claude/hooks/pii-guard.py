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
  - Private IP addresses (10.x, 172.16-31.x, 192.168.x) — advisory log only (not blocked)
  - Combination PII: 4+ labeled quasi-identifiers

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


def luhn_ok(digits: str) -> bool:
    total = 0
    for i, ch in enumerate(reversed(digits)):
        d = int(ch)
        if i % 2 == 1:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return total % 10 == 0


def check_credit_card(text: str) -> list[str]:
    for m in re.finditer(r"\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b", text):
        digits = re.sub(r"[-\s]", "", m.group(0))
        if luhn_ok(digits):
            return ["Credit card number pattern (16 digits, Luhn valid)"]
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
        r"(?i)\b(password|passwd|pass|pwd|secret|token)"
        r"\s*[=:]\s*['\"]?([^\s'\"]{8,})"
    )
    for match in re.finditer(pw_labels, text):
        val = match.group(2)
        low = val.lower()
        placeholders = [
            "xxx", "***", "your_", "change_me", "placeholder",
            "example", "dummy", "${", "env[", "os.environ",
            "process.env",
        ]
        if any(p in low for p in placeholders):
            continue
        # Code-shaped values are not secrets: calls, interpolation, refs
        if any(c in val for c in "(){}$"):
            continue
        # Identifier-shaped values (snake_case / camelCase) are code refs
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", val) and (
            "_" in val or re.search(r"[a-z][A-Z]", val)
        ):
            continue
        findings.append("Plaintext password/secret")
        break
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
    # Label separator. Prose occurrences ("関係 ", "chart title ") must NOT match:
    # only key-like positions do (JSON/YAML keys, CSV headers, key=value).
    # Whitespace alone is deliberately excluded -- it caused false positives that
    # blocked commits on purely technical documents.
    # An optional closing quote is allowed so that JSON/YAML keys ("department":)
    # match just as well as bare keys (department:).
    sep = r"""["']?\s*[：:=,]"""

    quasi_categories: list[tuple[str, list[str]]] = [
        (
            "company/org",
            [
                # company name, affiliation, employer, organization (JP)
                r"(?:会社名|所属|勤務先|企業名"
                r"|組織)" + sep,
                r"\b(?:company|org|organization|employer)\b" + sep,
            ],
        ),
        (
            "department",
            [
                # department, division, section, group, team (JP)
                # NOTE: bare 係 was dropped -- it matched the tail of 関係 / 係数
                # in technical prose far more often than an actual department label.
                r"(?:部署|部門|課|グループ|チーム)"
                + sep,
                r"\b(?:department|division|team|unit|section)\b" + sep,
            ],
        ),
        (
            "job_title",
            [
                # job title, position, role (JP)
                # NOTE: ポジション and 肩書き were previously mis-encoded
                # (㊤ / 肌) and therefore never matched. Fixed here.
                r"(?:役職|職位|職種|ポジション"
                r"|肩書き)" + sep,
                # Bare title/position/role are too common in code and docs to be a
                # useful signal; require the job- prefix instead.
                r"\bjob[\s_-]?(?:title|position|role)\b" + sep,
            ],
        ),
        (
            "age",
            [
                # age (JP: nenrei, sai, sai)
                # These already require a digit, so they stay specific without `sep`.
                r"(?:年齢|歳|才)[：:\s]*\d",
                r"\b(?:age)\b[\s:=]\s*\d",
                # NN years old (JP)
                r"\d{2}歳",
            ],
        ),
        (
            "gender",
            [
                # gender (JP: seibetsu)
                r"(?:性別)" + sep,
                r"\b(?:gender|sex)\b" + sep,
                # gender with value: male/female/other (JP)
                r"(?:性別)\s*[：:=,]\s*(?:男|女|その他"
                r"|male|female|other)",
            ],
        ),
        (
            "employee_id",
            [
                # employee number, staff ID (JP)
                # A separator is required here too. Without it, documentation that
                # merely discusses 従業員番号 as a concept counted as a match, which
                # pushed technical docs over the threshold on its own.
                # Real leaked data puts the term in a key position (CSV header,
                # JSON key, "label: value"), which the separator captures.
                r"(?:社員番号|従業員番号"
                r"|職員番号|スタッフID"
                r"|employee[\s_]?(?:id|number|no))" + sep,
            ],
        ),
        (
            "username",
            [
                # username, account, login ID (JP)
                r"(?:ユーザー名|アカウント"
                r"|ログインID)" + sep,
                r"\b(?:username|login|user[\s_]?id|account[\s_]?name)\b" + sep,
            ],
        ),
        (
            "hire_date",
            [
                # hire date, years of service (JP)
                r"(?:入社日|入社年月|勤続年数"
                r"|採用日)" + sep,
                r"\b(?:hire[\s_]?date|start[\s_]?date|joined)\b" + sep,
            ],
        ),
        (
            "nationality",
            [
                # nationality, birthplace, country of origin (JP)
                r"(?:国籍|出身地|出身国)" + sep,
                r"\b(?:nationality|citizenship|country[\s_]?of[\s_]?origin)\b" + sep,
            ],
        ),
        (
            "family",
            [
                # family structure, dependents, spouse, number of children (JP)
                r"(?:家族構成|扶養家族|配偶者"
                r"|子供の数)" + sep,
                # Bare "family" was dropped: it matches unrelated technical usage
                # such as "factor family" in this project's aggregation code.
                r"\b(?:dependents|spouse|marital[\s_]?status"
                r"|family[\s_]?(?:structure|members))\b" + sep,
            ],
        ),
    ]

    matched_categories: list[str] = []
    for cat_name, patterns in quasi_categories:
        for pat in patterns:
            if re.search(pat, text, re.I):
                matched_categories.append(cat_name)
                break  # one match per category is enough

    threshold = 4
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
    except Exception:
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
