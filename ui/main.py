# ui/main.py
from __future__ import annotations

import configparser
import base64
import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
import mimetypes
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.request import urlopen

from PySide6.QtCore import QProcess, Qt, QTimer, QUrl
from PySide6.QtGui import QAction, QFont, QIcon
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QProgressBar,
    QPlainTextEdit,
    QScrollArea,
    QSizePolicy,
    QTabWidget,
    QTextEdit,
    QToolButton,
    QVBoxLayout,
    QWidget,
    QTextBrowser,
)

# Optional: better local markdown rendering (tables/fenced code)
try:
    import markdown as mdlib
except Exception:
    mdlib = None

APP_NAME = "ITGlue to Hudu Migration Wizard"
ANSI_ESCAPE_RX = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
RUN_STAGE_RULES = [
    (re.compile(r"(Using Lastest Master Branch|Module imported from|Installed and imported HuduAPI|Module 'HuduAPI' imported|Current version .* compatible)", re.IGNORECASE), "Preparing APIs and modules", 8),
    (re.compile(r"(Loading Previous Companies Migration|Fetching Companies from IT Glue)", re.IGNORECASE), "Migrating companies", 15),
    (re.compile(r"(Loading Previous Locations Migration|Fetching Locations from IT Glue)", re.IGNORECASE), "Migrating locations", 24),
    (re.compile(r"(Loading Previous Websites Migration|Fetching Domains from IT Glue)", re.IGNORECASE), "Migrating domains and websites", 32),
    (re.compile(r"(Loading Previous Configurations Migration|Fetching Configurations from IT Glue)", re.IGNORECASE), "Migrating configurations", 40),
    (re.compile(r"(Loading Previous Contacts Migration|Fetching Contacts from IT Glue)", re.IGNORECASE), "Migrating contacts", 48),
    (re.compile(r"(Loading Previous Asset Layouts Migration|Fetching Flexible Asset Layouts from IT Glue)", re.IGNORECASE), "Migrating flexible asset layouts", 56),
    (re.compile(r"(Loading Previous Asset Migration|Fetching Flexible Assets from IT Glue)", re.IGNORECASE), "Migrating flexible assets", 64),
    (re.compile(r"Snapshot Point: Assets Migrated Continue\?", re.IGNORECASE), "Creating article shells", 72),
    (re.compile(r"Snapshot Point: Stub Articles Created Continue\?", re.IGNORECASE), "Populating article content", 78),
    (re.compile(r"(Loading Previous Paswords Migration|Fetching Passwords from IT Glue|Snapshot Point: Articles Created Continue\?)", re.IGNORECASE), "Migrating passwords", 86),
    (re.compile(r"Snapshot Point: Passwords Finished\. Continue\?", re.IGNORECASE), "Rewriting ITGlue links", 92),
    (re.compile(r"Snapshot Point: Company Notes URLs Replaced\. Continue\?", re.IGNORECASE), "Preparing wrap-up tasks", 95),
    (re.compile(r"IT Glue to Hudu Migration Complete", re.IGNORECASE), "Migration complete", 100),
]


# -----------------------------
# Repo root memory
# -----------------------------
def app_data_dir() -> Path:
    base = Path(os.environ.get("APPDATA", str(Path.home())))
    d = base / "Hudu Migration Wrapper" / "MigrationGUI"
    d.mkdir(parents=True, exist_ok=True)
    return d


def saved_repo_root_path() -> Path:
    return app_data_dir() / "repo_root.txt"


def load_saved_repo_root() -> Optional[Path]:
    p = saved_repo_root_path()
    if not p.exists():
        return None
    try:
        rr = Path(p.read_text(encoding="utf-8").strip()).expanduser().resolve()
        return rr if rr.exists() else None
    except Exception:
        return None


def save_repo_root(rr: Path) -> None:
    try:
        saved_repo_root_path().write_text(str(rr), encoding="utf-8")
    except Exception:
        pass


# -----------------------------
# Repo discovery
# -----------------------------
def looks_like_repo_root(p: Path) -> bool:
    return (
        (p / "environ.example").exists()
        and (p / "ITGlue-Hudu-Migration.ps1").exists()
        and (p / "README.md").exists()
    )


def discover_repo_root(start: Path) -> Optional[Path]:
    cur = start
    for _ in range(12):
        if looks_like_repo_root(cur):
            return cur
        cur = cur.parent
    return None


def repo_root_candidate() -> Path:
    env_override = os.environ.get("HUDU_MIGRATION_REPO_ROOT", "").strip()
    if env_override:
        p = Path(env_override).expanduser().resolve()
        if looks_like_repo_root(p):
            return p

    start = (
        Path(sys.executable).resolve().parent
        if getattr(sys, "frozen", False)
        else Path(__file__).resolve().parent
    )
    found = discover_repo_root(start)
    if found:
        return found

    saved = load_saved_repo_root()
    if saved and looks_like_repo_root(saved):
        return saved

    return start


def app_icon_candidate(repo_root: Optional[Path]) -> Optional[Path]:
    candidates: List[Path] = []
    if getattr(sys, "frozen", False):
        meipass = getattr(sys, "_MEIPASS", "")
        if meipass:
            candidates.append(Path(meipass) / "hudu_logo.png")
        candidates.append(Path(sys.executable).resolve().parent / "hudu_logo.png")
    if repo_root:
        candidates.append(repo_root / "ui" / "hudu_logo.png")
        candidates.append(repo_root / "hudu_logo.png")
    candidates.append(Path(__file__).resolve().parent / "hudu_logo.png")
    candidates.append(Path(__file__).resolve().parent.parent / "hudu_logo.png")

    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


# -----------------------------
# GitHub URL detection (fork/branch aware)
# -----------------------------
GITHUB_HOSTS = {"github.com", "www.github.com"}


def _parse_github_remote_url(remote: str) -> Optional[str]:
    remote = (remote or "").strip()
    if not remote:
        return None

    m = re.match(
        r"^git@(?P<host>[^:]+):(?P<org>[^/]+)/(?P<repo>[^/]+?)(?:\.git)?$",
        remote,
        re.IGNORECASE,
    )
    if m and m.group("host").lower() in GITHUB_HOSTS:
        return f"https://github.com/{m.group('org')}/{m.group('repo')}"

    m = re.match(
        r"^https?://(?P<host>[^/]+)/(?P<org>[^/]+)/(?P<repo>[^/]+?)(?:\.git)?/?$",
        remote,
        re.IGNORECASE,
    )
    if m and m.group("host").lower() in GITHUB_HOSTS:
        return f"https://github.com/{m.group('org')}/{m.group('repo')}"

    return None


def _read_git_config_origin_url(repo_root: Path) -> Optional[str]:
    git_dir = repo_root / ".git"
    if not git_dir.exists():
        return None

    if git_dir.is_file():
        try:
            txt = git_dir.read_text(encoding="utf-8", errors="replace")
            m = re.search(r"gitdir:\s*(.+)\s*$", txt, re.IGNORECASE | re.MULTILINE)
            if m:
                git_dir = (repo_root / m.group(1).strip()).resolve()
        except Exception:
            return None

    cfg = git_dir / "config"
    if not cfg.exists():
        return None

    cp = configparser.ConfigParser()
    try:
        cp.read(cfg, encoding="utf-8")
    except Exception:
        return None

    for section in cp.sections():
        if section.lower() == 'remote "origin"':
            return cp.get(section, "url", fallback=None)

    for section in cp.sections():
        if section.lower().startswith('remote "'):
            return cp.get(section, "url", fallback=None)

    return None


def _git_try(args: List[str], cwd: Path) -> Optional[str]:
    try:
        kwargs = {
            "cwd": str(cwd),
            "capture_output": True,
            "text": True,
            "check": False,
        }
        if os.name == "nt":
            kwargs["creationflags"] = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        p = subprocess.run(args, **kwargs)
        if p.returncode != 0:
            return None
        out = (p.stdout or "").strip()
        return out or None
    except Exception:
        return None


def detect_github_repo_and_branch(repo_root: Path) -> Tuple[Optional[str], Optional[str]]:
    origin = _git_try(["git", "remote", "get-url", "origin"], repo_root)
    if not origin:
        origin = _read_git_config_origin_url(repo_root)
    repo_url = _parse_github_remote_url(origin) if origin else None

    branch = _git_try(["git", "rev-parse", "--abbrev-ref", "HEAD"], repo_root)
    if branch == "HEAD":
        branch = None

    if not branch:
        ref = _git_try(["git", "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD"], repo_root)
        if ref and ref.startswith("refs/remotes/origin/"):
            branch = ref.split("/")[-1]

    return repo_url, branch


# -----------------------------
# Markdown preprocessing to better match GitHub
# -----------------------------
ADMON_LINE_RX = re.compile(r'^\s*>\s*\[\!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$', re.IGNORECASE)
IMG_MD_RX = re.compile(r'!\[([^\]]*)\]\(([^)]+)\)')
IMG_HTML_RX = re.compile(r'(<img\b[^>]*?\bsrc\s*=\s*)(["\'])(.+?)(\2)', re.IGNORECASE)
IMG_DIMENSION_ATTR_RX = re.compile(r"\s+(width|height)\s*=\s*(['\"])[^'\"]*\2", re.IGNORECASE)


def rewrite_github_admonitions(md_text: str) -> str:
    """
    Converts GitHub admonitions:
      > [!CAUTION]
      > text
    into:
      > **CAUTION:** text
    so python-markdown renders something readable.
    """
    lines = md_text.splitlines()
    out: List[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = ADMON_LINE_RX.match(line)
        if not m:
            out.append(line)
            i += 1
            continue

        kind = m.group(1).upper()
        block: List[str] = []
        i += 1
        while i < len(lines) and lines[i].lstrip().startswith(">"):
            # strip leading '>' and optional space
            block.append(re.sub(r'^\s*>\s?', '', lines[i]).rstrip())
            i += 1

        out.append(f"> **{kind}:**")
        for b in block:
            out.append(f"> {b}".rstrip())
        out.append("")  # spacer
    return "\n".join(out)


def _rewrite_readme_asset_url(url: str, repo_url: Optional[str], branch: Optional[str]) -> str:
    branch = branch or "main"
    raw_base = None

    if repo_url and repo_url.startswith("https://github.com/"):
        parts = repo_url.rstrip("/").split("/")
        if len(parts) >= 5:
            org = parts[-2]
            repo = parts[-1]
            raw_base = f"https://raw.githubusercontent.com/{org}/{repo}/{branch}/"

    if (
        url.startswith("https://raw.githubusercontent.com/")
        or url.startswith("file:")
        or url.startswith("data:")
    ):
        return url

    blob = re.match(r"^https?://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.*)$", url)
    if blob:
        o, r, br, path = blob.groups()
        return f"https://raw.githubusercontent.com/{o}/{r}/{br}/{path}"

    if raw_base and not re.match(r"^https?://", url):
        return f"{raw_base}{url.lstrip('./')}"

    return url


def rewrite_image_links_to_raw(md_text: str, repo_url: Optional[str], branch: Optional[str]) -> str:
    """
    Rewrites image links so QTextBrowser can load them:
      - relative -> raw.githubusercontent.com/org/repo/branch/relative
      - github blob -> raw.githubusercontent.com/org/repo/branch/path
    """
    def repl(m: re.Match) -> str:
        alt = m.group(1)
        url = m.group(2).strip()
        rewritten = _rewrite_readme_asset_url(url, repo_url, branch)
        return f"![{alt}]({rewritten})" if rewritten != url else m.group(0)

    return IMG_MD_RX.sub(repl, md_text)


def rewrite_html_image_sources(md_text: str, repo_url: Optional[str], branch: Optional[str]) -> str:
    def repl(m: re.Match) -> str:
        prefix, quote, url, _ = m.groups()
        rewritten = _rewrite_readme_asset_url(url.strip(), repo_url, branch)
        return f"{prefix}{quote}{rewritten}{quote}"

    return IMG_HTML_RX.sub(repl, md_text)


def strip_html_image_dimensions(md_text: str) -> str:
    def repl(m: re.Match) -> str:
        tag = m.group(0)
        return IMG_DIMENSION_ATTR_RX.sub("", tag)

    return re.sub(r"<img\b[^>]*>", repl, md_text, flags=re.IGNORECASE)


def fetch_url_text(url: str) -> Optional[str]:
    try:
        with urlopen(url, timeout=15) as resp:
            charset = resp.headers.get_content_charset() or "utf-8"
            return resp.read().decode(charset, errors="replace")
    except Exception:
        return None


def inline_remote_images(html_text: str) -> str:
    def repl(m: re.Match) -> str:
        prefix, quote, url, _ = m.groups()
        if not re.match(r"^https?://", url, re.IGNORECASE):
            return m.group(0)

        try:
            with urlopen(url, timeout=20) as resp:
                data = resp.read()
                content_type = resp.headers.get_content_type()
        except Exception:
            return m.group(0)

        if not content_type or content_type == "application/octet-stream":
            guessed, _ = mimetypes.guess_type(url)
            content_type = guessed or "application/octet-stream"

        b64 = base64.b64encode(data).decode("ascii")
        return f'{prefix}{quote}data:{content_type};base64,{b64}{quote}'

    return IMG_HTML_RX.sub(repl, html_text)


# -----------------------------
# PowerShell helpers
# -----------------------------
def which(cmd: str) -> Optional[str]:
    path = os.environ.get("PATH", "")
    exts = os.environ.get("PATHEXT", ".EXE;.BAT;.CMD").split(";") if os.name == "nt" else [""]
    for folder in path.split(os.pathsep):
        folder = folder.strip().strip('"')
        if not folder:
            continue
        base = Path(folder) / cmd
        if base.exists():
            return str(base)
        if os.name == "nt" and "." not in cmd:
            for ext in exts:
                p = Path(folder) / (cmd + ext)
                if p.exists():
                    return str(p)
    return None


def detect_pwsh() -> Optional[str]:
    return which("pwsh.exe") or which("pwsh")


def ps_single_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def clean_console_line(text: str) -> str:
    return ANSI_ESCAPE_RX.sub("", text).replace("\ufeff", "").rstrip("\r")


def output_line_html(text: str) -> str:
    escaped = html.escape(text if text else " ")
    color = "#d7d7d7"
    weight = "normal"

    if "PowerShell is in NonInteractive mode" in text or "Read-Host:" in text or "Cannot" in text:
        color = "#f48771"
    elif text.startswith("Warning") or "WARNING:" in text:
        color = "#dcdcaa"
    elif text.startswith("Fetching ") or text.startswith("Loading ") or text.startswith("Retrieved "):
        color = "#4fc1ff"
    elif text.startswith("Starting ") or text.startswith("Migrating "):
        color = "#c586c0"
    elif "Migration Complete" in text or "compatible" in text or "Ready." in text:
        color = "#6a9955"
        weight = "600"
    elif text.startswith("wrapup "):
        color = "#ce9178"
        weight = "600"
    elif text.startswith("################################################") or text.startswith("<*><*><*>") or text.startswith("#        IT Glue"):
        color = "#569cd6"
        weight = "600"

    return f'<div style="color:{color}; font-weight:{weight}; white-space:pre-wrap;">{escaped}</div>'


PRIMARY_BUTTON_STYLE = (
    "QPushButton {"
    " background-color: #0b57d0;"
    " color: white;"
    " border: 1px solid #0842a0;"
    " border-radius: 4px;"
    " padding: 6px 12px;"
    " font-weight: 600;"
    "}"
    "QPushButton:hover { background-color: #1a67db; }"
    "QPushButton:pressed { background-color: #0842a0; }"
    "QPushButton:disabled { background-color: #9bb7e8; color: #eef3fb; border-color: #9bb7e8; }"
)

SECONDARY_BUTTON_STYLE = (
    "QPushButton {"
    " color: #334155;"
    " background-color: #f4f6f8;"
    " border: 1px solid #cbd5e1;"
    " border-radius: 4px;"
    " padding: 5px 10px;"
    "}"
    "QPushButton:hover { background-color: #e8edf3; }"
    "QPushButton:pressed { background-color: #dbe4ee; }"
)


# -----------------------------
# environ.example parsing
# -----------------------------
SETTINGS_BLOCK_START_RX = re.compile(r"^\s*\$settings\s*=\s*@\{\s*$")
SETTINGS_BLOCK_END_RX = re.compile(r"^\s*\}\s*$")
SETTINGS_KV_RX = re.compile(
    r"^(?P<indent>\s*)(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?P<rhs>.*?)(?P<trailing>\s*(?:\#.*)?)$"
)
VAR_ASSIGN_RX = re.compile(
    r"^(?P<indent>\s*)\$(?P<var>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?P<rhs>.*?)(?P<trailing>\s*(?:\#.*)?)$"
)
INITTYPE_RX = re.compile(r"^\s*\$InitType\b", re.IGNORECASE)


def rhs_to_display(rhs: str) -> str:
    s = rhs.strip()
    m = re.match(r'^(["\'])(.*)\1$', s)
    return m.group(2) if m else s


def ps_dq(s: str) -> str:
    return '"' + s.replace('"', '`"') + '"'


def normalize_user_path(value: str) -> Path:
    text = value.strip().strip('"').strip("'")
    expanded = os.path.expandvars(os.path.expanduser(text))
    return Path(expanded)


def is_export_path_setting_key(key: str) -> bool:
    k = key.lower()
    return ("export" in k) and ("path" in k)


@dataclass
class Entry:
    kind: str  # "settings" or "var"
    name: str
    line_no: int
    indent: str
    trailing: str
    rhs: str


def parse_entries(lines: List[str]) -> Dict[Tuple[str, str], Entry]:
    init_idx = 0
    for i, line in enumerate(lines):
        if INITTYPE_RX.match(line):
            init_idx = i
            break

    entries: Dict[Tuple[str, str], Entry] = {}
    in_settings = False

    for i in range(init_idx, len(lines)):
        line = lines[i]

        if SETTINGS_BLOCK_START_RX.match(line):
            in_settings = True
            continue
        if in_settings and SETTINGS_BLOCK_END_RX.match(line):
            in_settings = False
            continue

        if in_settings:
            m = SETTINGS_KV_RX.match(line)
            if m:
                e = Entry("settings", m.group("key"), i, m.group("indent"), m.group("trailing") or "", m.group("rhs").strip())
                entries[(e.kind, e.name)] = e
            continue

        m = VAR_ASSIGN_RX.match(line)
        if m:
            e = Entry("var", m.group("var"), i, m.group("indent"), m.group("trailing") or "", m.group("rhs").strip())
            entries[(e.kind, e.name)] = e

    return entries


# -----------------------------
# Main window
# -----------------------------
class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(APP_NAME)
        self.resize(1250, 920)

        self.rr = repo_root_candidate()
        self.rr = self._ensure_repo_root(self.rr)
        icon_path = app_icon_candidate(self.rr)
        if icon_path:
            self.setWindowIcon(QIcon(str(icon_path)))

        self.template_path = self.rr / "environ.example"
        self.output_path = self.rr / "migrationrun.ps1"
        self.run_log_path = self.rr / "migrationrun.log"
        self.manual_actions_path = self.rr / "ManualActions.html"

        self.template_lines: List[str] = []
        self.entries: Dict[Tuple[str, str], Entry] = {}
        self._run_process: Optional[QProcess] = None
        self._run_buffer = ""
        self._tail_buffer = ""
        self._run_mode = "Idle"

        # log tail (Run Output)
        self._tail_timer = QTimer(self)
        self._tail_timer.setInterval(500)
        self._tail_timer.timeout.connect(self._tail_log_tick)
        self._tail_pos = 0

        self.tabs = QTabWidget()
        self.setCentralWidget(self.tabs)

        self._build_menu()
        self._build_help_tab()
        self._build_setup_tab()
        self._build_preview_tab()
        self._build_output_tab()

        self._load_template()
        self._apply_saved_settings()
        self._refresh()

    def _ensure_repo_root(self, candidate: Path) -> Path:
        if looks_like_repo_root(candidate):
            save_repo_root(candidate)
            return candidate

        QMessageBox.warning(
            self,
            "Repo not found",
            "Couldn't locate the migration repo automatically.\n\n"
            "Select the folder that contains environ.example, ITGlue-Hudu-Migration.ps1, and README.md.",
        )
        chosen = QFileDialog.getExistingDirectory(self, "Select Repo Root", str(candidate))
        if chosen:
            p = Path(chosen).resolve()
            if looks_like_repo_root(p):
                save_repo_root(p)
                return p
        QMessageBox.information(
            self,
            "Limited startup",
            "Starting without a confirmed repo root. You can use File > Change Repo Root to point the GUI at the migration repo.",
        )
        return candidate

    # UI helpers
    def _make_scrollable(self, content: QWidget) -> QScrollArea:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.NoFrame)
        scroll.setWidget(content)
        return scroll

    def _group(self, title: str) -> QGroupBox:
        g = QGroupBox(title)
        g.setStyleSheet("QGroupBox { font-weight: 600; }")
        return g

    def _secret_row(self, initial: str) -> Tuple[QLineEdit, QWidget]:
        le = QLineEdit(initial)
        le.setEchoMode(QLineEdit.Password)
        btn = QToolButton()
        btn.setText("Reveal")
        btn.setCheckable(True)

        def toggle(checked: bool) -> None:
            le.setEchoMode(QLineEdit.Normal if checked else QLineEdit.Password)
            btn.setText("Hide" if checked else "Reveal")

        btn.toggled.connect(toggle)

        row = QHBoxLayout()
        row.addWidget(le)
        row.addWidget(btn)
        wrap = QWidget()
        wrap.setLayout(row)
        return le, wrap

    # Menu
    def _build_menu(self) -> None:
        m = self.menuBar()
        file_menu = m.addMenu("&File")

        change_repo = QAction("Change Repo Root…", self)
        change_repo.triggered.connect(self._change_repo_root)
        file_menu.addAction(change_repo)

        exit_action = QAction("Exit", self)
        exit_action.triggered.connect(self.close)
        file_menu.addAction(exit_action)

    def _change_repo_root(self) -> None:
        chosen = QFileDialog.getExistingDirectory(self, "Select Repo Root", str(self.rr))
        if not chosen:
            return
        p = Path(chosen).resolve()
        if not looks_like_repo_root(p):
            QMessageBox.critical(
                self,
                "Invalid repo root",
                "That folder must contain environ.example, ITGlue-Hudu-Migration.ps1, and README.md.",
            )
            return

        self.rr = p
        save_repo_root(p)
        icon_path = app_icon_candidate(self.rr)
        if icon_path:
            self.setWindowIcon(QIcon(str(icon_path)))

        self.template_path = self.rr / "environ.example"
        self.output_path = self.rr / "migrationrun.ps1"
        self.run_log_path = self.rr / "migrationrun.log"
        self.manual_actions_path = self.rr / "ManualActions.html"

        self._load_readme_local()
        self._load_template()
        self._refresh()

    # -----------------------------
    # Help tab
    # -----------------------------
    def _github_readme_url(self) -> str:
        repo_url, branch = detect_github_repo_and_branch(self.rr)
        branch = branch or "main"
        if repo_url:
            return f"{repo_url}/blob/{branch}/README.md"
        return "https://github.com/Hudu-Technologies-Inc/ITGlue-Hudu-Migration/blob/main/README.md"

    def _github_raw_readme_url(self) -> str:
        repo_url, branch = detect_github_repo_and_branch(self.rr)
        branch = branch or "main"
        if repo_url and repo_url.startswith("https://github.com/"):
            parts = repo_url.rstrip("/").split("/")
            if len(parts) >= 5:
                org = parts[-2]
                repo = parts[-1]
                return f"https://raw.githubusercontent.com/{org}/{repo}/{branch}/README.md"
        return "https://raw.githubusercontent.com/Hudu-Technologies-Inc/ITGlue-Hudu-Migration/main/README.md"

    def _build_help_tab(self) -> None:
        w = QWidget()
        layout = QVBoxLayout(w)

        title = QLabel("Help / README")
        title.setFont(QFont("", 11))
        layout.addWidget(title)

        self.help_detected = QLabel("")
        self.help_detected.setTextInteractionFlags(Qt.TextSelectableByMouse)
        layout.addWidget(self.help_detected)

        self.help_view = QTextBrowser()
        self.help_view.setOpenExternalLinks(True)
        self.help_view.setReadOnly(True)
        self.help_view.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        layout.addWidget(self.help_view)

        btn_row = QHBoxLayout()
        self.help_reload_btn = QPushButton("Reload")
        self.help_reload_local_btn = QPushButton("Reload (local only)")
        self.help_open_btn = QPushButton("Open GitHub README (recommended)")
        self.help_copy_btn = QPushButton("Copy GitHub link")
        btn_row.addWidget(self.help_reload_btn)
        btn_row.addWidget(self.help_reload_local_btn)
        btn_row.addWidget(self.help_open_btn)
        btn_row.addWidget(self.help_copy_btn)
        btn_row.addStretch(1)
        layout.addLayout(btn_row)

        self.help_reload_btn.clicked.connect(self._load_readme)
        self.help_reload_local_btn.clicked.connect(self._load_readme_local)
        self.help_open_btn.clicked.connect(lambda: os.startfile(self._github_readme_url()))
        self.help_copy_btn.clicked.connect(self._copy_github_link)

        self.tabs.addTab(w, "Help")
        self._load_readme()

    def _copy_github_link(self) -> None:
        url = self._github_readme_url()
        QApplication.clipboard().setText(url)
        QMessageBox.information(self, "Copied", "GitHub README link copied to clipboard.")

    def _render_readme(self, md_text: str, repo_url: Optional[str], branch: Optional[str]) -> None:
        # Improve GFM-only features:
        md_text = rewrite_github_admonitions(md_text)
        md_text = rewrite_image_links_to_raw(md_text, repo_url, branch)
        md_text = rewrite_html_image_sources(md_text, repo_url, branch)
        md_text = strip_html_image_dimensions(md_text)

        try:
            base = QUrl.fromLocalFile(str(self.rr) + os.sep)
            self.help_view.document().setBaseUrl(base)
        except Exception:
            pass

        if mdlib is not None:
            try:
                html = mdlib.markdown(md_text, extensions=["extra", "sane_lists", "toc"], output_format="html5")
                html = inline_remote_images(html)
                styled = f"""
                <html><head><meta charset="utf-8">
                <style>
                  body {{ font-family: Segoe UI, Arial, sans-serif; font-size: 10.5pt; }}
                  code, pre {{ font-family: Consolas, monospace; }}
                  pre {{ padding: 8px; background: #f5f5f5; overflow-x: auto; }}
                  table {{ border-collapse: collapse; }}
                  td, th {{ border: 1px solid #ddd; padding: 6px; }}
                  img {{ max-width: 100%; height: auto; image-rendering: auto; }}
                  blockquote {{ border-left: 4px solid #ddd; margin: 8px 0; padding: 4px 12px; color: #333; }}
                </style></head><body>{html}</body></html>
                """
                self.help_view.setHtml(styled)
                return
            except Exception:
                pass

        self.help_view.setMarkdown(md_text)

    def _load_readme(self) -> None:
        repo_url, branch = detect_github_repo_and_branch(self.rr)
        branch_disp = branch or "(unknown → main)"
        repo_disp = repo_url or "(unknown remote)"
        raw_url = self._github_raw_readme_url()
        md_text = fetch_url_text(raw_url)
        if md_text is not None:
            self.help_detected.setText(f"Detected: {repo_disp} @ {branch_disp} | Source: GitHub")
            self._render_readme(md_text, repo_url, branch)
            return

        self.help_detected.setText(f"Detected: {repo_disp} @ {branch_disp} | Source: local fallback")
        self._load_readme_local()

    def _load_readme_local(self) -> None:
        repo_url, branch = detect_github_repo_and_branch(self.rr)
        branch_disp = branch or "(unknown → main)"
        repo_disp = repo_url or "(unknown remote)"
        self.help_detected.setText(f"Detected: {repo_disp} @ {branch_disp} | Source: local")

        readme = self.rr / "README.md"
        if not readme.exists():
            self.help_view.setPlainText(f"README not found at:\n{readme}")
            return
        md_text = readme.read_text(encoding="utf-8", errors="replace")
        self._render_readme(md_text, repo_url, branch)

    # -----------------------------
    # Setup tab / UI
    # -----------------------------
    def _build_setup_tab(self) -> None:
        root = QWidget()
        layout = QVBoxLayout(root)

        header = QLabel(
            "Configure the migration, then start it directly from this app. "
            "Use the PowerShell fallback only for advanced flows that still need live prompts."
        )
        header.setWordWrap(True)
        header.setFont(QFont("", 11))
        layout.addWidget(header)

        core = self._group("Core Settings")
        cf = QFormLayout(core)

        self.repo_label = QLabel(str(self.rr))
        self.repo_label.setTextInteractionFlags(Qt.TextSelectableByMouse)

        self.template_label = QLabel(str(self.template_path))
        self.template_label.setTextInteractionFlags(Qt.TextSelectableByMouse)

        self.itg_url = QLineEdit("")
        self.itg_endpoint = QLineEdit("")
        self.hudu_base = QLineEdit("")
        self.internal_company = QLineEdit("")

        self.itg_key, itg_wrap = self._secret_row("")
        self.hudu_key, hudu_wrap = self._secret_row("")

        self.export_le = QLineEdit(r"c:\temp\export")
        export_btn = QPushButton("Browse…")
        export_btn.clicked.connect(self._browse_export)
        erow = QHBoxLayout()
        erow.addWidget(self.export_le)
        erow.addWidget(export_btn)
        ewrap = QWidget()
        ewrap.setLayout(erow)

        self.cb_config_prefix = QCheckBox("Use prefix")
        self.cb_config_prefix.setChecked(True)
        self.config_prefix = QLineEdit("ITG-")
        config_prefix_row = QHBoxLayout()
        config_prefix_row.addWidget(self.cb_config_prefix)
        config_prefix_row.addWidget(self.config_prefix)
        config_prefix_wrap = QWidget()
        config_prefix_wrap.setLayout(config_prefix_row)

        self.cb_fa_prefix = QCheckBox("Use prefix")
        self.cb_fa_prefix.setChecked(True)
        self.fa_prefix = QLineEdit("ITG-")
        fa_prefix_row = QHBoxLayout()
        fa_prefix_row.addWidget(self.cb_fa_prefix)
        fa_prefix_row.addWidget(self.fa_prefix)
        fa_prefix_wrap = QWidget()
        fa_prefix_wrap.setLayout(fa_prefix_row)

        def toggle_prefix_inputs() -> None:
            self.config_prefix.setEnabled(self.cb_config_prefix.isChecked())
            self.fa_prefix.setEnabled(self.cb_fa_prefix.isChecked())

        self.cb_config_prefix.stateChanged.connect(lambda _=None: toggle_prefix_inputs())
        self.cb_fa_prefix.stateChanged.connect(lambda _=None: toggle_prefix_inputs())
        toggle_prefix_inputs()

        cf.addRow("Repo root:", self.repo_label)
        cf.addRow("environ.example:", self.template_label)
        cf.addRow("ITGlue URL:", self.itg_url)
        cf.addRow("ITGlue API Endpoint:", self.itg_endpoint)
        cf.addRow("ITGlue API Key:", itg_wrap)
        cf.addRow("Hudu Base Domain:", self.hudu_base)
        cf.addRow("Hudu API Key:", hudu_wrap)
        cf.addRow("Internal Company (name):", self.internal_company)
        cf.addRow("Configs asset layout prefix:", config_prefix_wrap)
        cf.addRow("Flexible asset layout prefix:", fa_prefix_wrap)
        cf.addRow("ITGlue Export Path:", ewrap)
        layout.addWidget(core)

        common = self._group("Common Options")
        cl = QVBoxLayout(common)

        self.cb_resume = QCheckBox("Resume previous run if logs exist")
        self.cb_noninteractive = QCheckBox("Non-interactive mode (recommended for GUI)")
        self.cb_split_configs = QCheckBox("Split configurations into individual layouts")
        self.cb_include_itgid = QCheckBox("Include ITGlue ID in migrated items")
        self.cb_scoped = QCheckBox("Scoped migration (advanced/testing)")
        self.cb_merge_org_types = QCheckBox("Merge selected org types into a single Hudu company")
        self.cb_skip_integrator = QCheckBox("Skip integrator ('auto') layouts")

        for cb in (
            self.cb_resume,
            self.cb_noninteractive,
            self.cb_split_configs,
            self.cb_include_itgid,
            self.cb_scoped,
            self.cb_merge_org_types,
            self.cb_skip_integrator,
        ):
            cl.addWidget(cb)
        layout.addWidget(common)

        imp = self._group("What to Import")
        il = QVBoxLayout(imp)

        self.cb_companies = QCheckBox("Companies")
        self.cb_locations = QCheckBox("Locations")
        self.cb_domains = QCheckBox("Domains")
        self.cb_disable_webmon = QCheckBox("Disable website monitoring (recommended)")
        self.cb_configurations = QCheckBox("Configurations")
        self.cb_contacts = QCheckBox("Contacts")
        self.cb_flex_layouts = QCheckBox("Flexible Asset Layouts")
        self.cb_flex_assets = QCheckBox("Flexible Assets")
        self.cb_articles = QCheckBox("Articles / Docs")
        self.cb_passwords = QCheckBox("Passwords")

        for cb in (
            self.cb_companies,
            self.cb_locations,
            self.cb_domains,
            self.cb_disable_webmon,
            self.cb_configurations,
            self.cb_contacts,
            self.cb_flex_layouts,
            self.cb_flex_assets,
            self.cb_articles,
            self.cb_passwords,
        ):
            il.addWidget(cb)
        layout.addWidget(imp)

        adv = self._group("Advanced settings (uncommon)")
        af = QFormLayout(adv)

        self.cb_custom_branded = QCheckBox('customBrandedDomain (check for "y")')
        self.cb_custom_branded.setChecked(False)

        self.cb_flags = QCheckBox("Apply flags and flag types (requires Hudu ≥ 2.40)")
        self.cb_flags.setChecked(True)

        self.itg_custom_domains = QLineEdit("")
        self.itg_custom_domains.setEnabled(False)

        def toggle_custom_domains() -> None:
            self.itg_custom_domains.setEnabled(self.cb_custom_branded.isChecked())
            if not self.cb_custom_branded.isChecked():
                self.itg_custom_domains.setText("")

        self.cb_custom_branded.stateChanged.connect(lambda _=None: toggle_custom_domains())

        af.addRow("$settings.customBrandedDomain:", self.cb_custom_branded)
        af.addRow("$settings.ITGCustomDomains:", self.itg_custom_domains)
        af.addRow("apply flags/flag types:", self.cb_flags)
        layout.addWidget(adv)

        files = self._group("Generated Files")
        f2 = QFormLayout(files)
        self.output_label = QLabel(str(self.output_path))
        self.output_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.log_label = QLabel(str(self.run_log_path))
        self.log_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.report_label = QLabel(str(self.manual_actions_path))
        self.report_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.settings_label = QLabel(str(self._settings_file_path()))
        self.settings_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        f2.addRow("Run Script:", self.output_label)
        f2.addRow("Run Log:", self.log_label)
        f2.addRow("Manual Actions Report:", self.report_label)
        f2.addRow("Saved Settings:", self.settings_label)
        layout.addWidget(files)

        primary_btn_row = QHBoxLayout()
        self.btn_save_settings = QPushButton("Save settings")
        self.btn_run = QPushButton("Start Migration")
        self.btn_save_settings.setStyleSheet(PRIMARY_BUTTON_STYLE)
        self.btn_run.setStyleSheet(PRIMARY_BUTTON_STYLE)

        secondary_btn_row = QHBoxLayout()
        self.btn_run_console = QPushButton("Run in PowerShell")
        self.btn_open_script = QPushButton("Open migrationrun.ps1")
        self.btn_reveal_script = QPushButton("Reveal Script Folder")
        self.btn_open_log = QPushButton("Open migrationrun.log")
        self.btn_open_log.setEnabled(False)
        for btn in (self.btn_run_console, self.btn_open_script, self.btn_reveal_script, self.btn_open_log):
            btn.setStyleSheet(SECONDARY_BUTTON_STYLE)

        self.btn_save_settings.clicked.connect(self._save_settings)
        self.btn_run.clicked.connect(self._start_migration)
        self.btn_run_console.clicked.connect(self._run_in_console)
        self.btn_open_script.clicked.connect(self._open_run_script)
        self.btn_reveal_script.clicked.connect(self._reveal_run_script)
        self.btn_open_log.clicked.connect(self._open_run_log)

        primary_btn_row.addWidget(self.btn_save_settings)
        primary_btn_row.addWidget(self.btn_run)
        primary_btn_row.addStretch(1)
        layout.addLayout(primary_btn_row)

        secondary_btn_row.addWidget(self.btn_run_console)
        secondary_btn_row.addWidget(self.btn_open_script)
        secondary_btn_row.addWidget(self.btn_reveal_script)
        secondary_btn_row.addWidget(self.btn_open_log)
        secondary_btn_row.addStretch(1)
        layout.addLayout(secondary_btn_row)

        self.status = QLabel("")
        self.status.setWordWrap(True)
        layout.addWidget(self.status)

        # Hooks
        for w in (
            self.itg_url,
            self.itg_endpoint,
            self.itg_key,
            self.hudu_base,
            self.hudu_key,
            self.internal_company,
            self.config_prefix,
            self.fa_prefix,
            self.export_le,
            self.itg_custom_domains,
        ):
            w.textChanged.connect(self._refresh)

        for cb in (
            self.cb_resume,
            self.cb_noninteractive,
            self.cb_split_configs,
            self.cb_include_itgid,
            self.cb_scoped,
            self.cb_merge_org_types,
            self.cb_skip_integrator,
            self.cb_companies,
            self.cb_locations,
            self.cb_domains,
            self.cb_disable_webmon,
            self.cb_configurations,
            self.cb_contacts,
            self.cb_flex_layouts,
            self.cb_flex_assets,
            self.cb_articles,
            self.cb_passwords,
            self.cb_custom_branded,
            self.cb_flags,
            self.cb_config_prefix,
            self.cb_fa_prefix,
        ):
            cb.stateChanged.connect(self._refresh)

        layout.addStretch(1)
        self.tabs.addTab(self._make_scrollable(root), "Setup")

    def _build_preview_tab(self) -> None:
        w = QWidget()
        layout = QVBoxLayout(w)
        self.preview = QPlainTextEdit()
        self.preview.setReadOnly(True)
        layout.addWidget(self.preview)
        self.tabs.addTab(w, "Preview")

    def _build_output_tab(self) -> None:
        w = QWidget()
        layout = QVBoxLayout(w)

        header = QLabel("Watch migration progress here. In-app runs stream live PowerShell output, and the fallback PowerShell mode tails the shared log.")
        header.setWordWrap(True)
        layout.addWidget(header)

        self.run_mode_label = QLabel("Run Mode: Idle")
        self.run_stage_label = QLabel("Stage: Waiting to start")
        self.run_detail_label = QLabel("Current item: n/a")
        self.run_detail_label.setWordWrap(True)
        self.run_progress = QProgressBar()
        self.run_progress.setRange(0, 100)
        self.run_progress.setValue(0)
        self.run_progress.setFormat("%p%")

        layout.addWidget(self.run_mode_label)
        layout.addWidget(self.run_stage_label)
        layout.addWidget(self.run_detail_label)
        layout.addWidget(self.run_progress)

        run_btn_row = QHBoxLayout()
        self.btn_stop_run = QPushButton("Stop In-App Run")
        self.btn_stop_run.setEnabled(False)
        self.btn_open_report = QPushButton("Open ManualActions.html")
        self.btn_open_report.setEnabled(False)

        self.btn_stop_run.clicked.connect(self._stop_migration)
        self.btn_open_report.clicked.connect(self._open_manual_actions_report)

        run_btn_row.addWidget(self.btn_stop_run)
        run_btn_row.addWidget(self.btn_open_report)
        run_btn_row.addStretch(1)
        layout.addLayout(run_btn_row)

        self.output_view = QTextEdit()
        self.output_view.setReadOnly(True)
        self.output_view.document().setMaximumBlockCount(20000)
        self.output_view.setStyleSheet(
            "QTextEdit {"
            " background-color: #0c0c0c;"
            " color: #d7d7d7;"
            " selection-background-color: #264f78;"
            " border: 1px solid #202020;"
            " font-family: Consolas, 'Cascadia Mono', monospace;"
            " font-size: 10pt;"
            "}"
        )
        layout.addWidget(self.output_view)

        self.tabs.addTab(w, "Run Output")

    # -----------------------------
    # Load template defaults
    # -----------------------------
    def _load_template(self) -> None:
        self.repo_label.setText(str(self.rr))
        self.template_label.setText(str(self.template_path))
        self.output_label.setText(str(self.output_path))
        self.log_label.setText(str(self.run_log_path))
        self.report_label.setText(str(self.manual_actions_path))
        self.btn_open_script.setEnabled(self.output_path.exists())
        self.btn_reveal_script.setEnabled(self.output_path.parent.exists())

        if not self.template_path.exists():
            QMessageBox.critical(self, "Missing template", f"Template not found:\n{self.template_path}")
            return

        self.template_lines = self.template_path.read_text(encoding="utf-8", errors="replace").splitlines()
        self.entries = parse_entries(self.template_lines)

        def get(kind: str, name: str) -> Optional[str]:
            e = self.entries.get((kind, name))
            return rhs_to_display(e.rhs) if e else None

        self.hudu_base.setText(get("settings", "HuduBaseDomain") or "")
        self.itg_url.setText(get("settings", "ITGURL") or "")
        self.itg_endpoint.setText(get("settings", "ITGAPIEndpoint") or "")
        self.internal_company.setText(get("settings", "InternalCompany") or "")
        con_prefix = get("settings", "ConPromptPrefix")
        self.cb_config_prefix.setChecked(True)
        self.config_prefix.setText(con_prefix if con_prefix else "ITG-")
        fa_prefix = get("settings", "FAPromptPrefix")
        self.cb_fa_prefix.setChecked(True)
        self.fa_prefix.setText(fa_prefix if fa_prefix else "ITG-")
        self.config_prefix.setEnabled(self.cb_config_prefix.isChecked())
        self.fa_prefix.setEnabled(self.cb_fa_prefix.isChecked())

        for (k, n), _e in self.entries.items():
            if k == "settings" and is_export_path_setting_key(n):
                v = get("settings", n)
                if v:
                    self.export_le.setText(v)
                break

        self.itg_key.setText(get("var", "ITGKey") or "")
        self.hudu_key.setText(get("var", "HuduApiKey") or get("var", "HuduAPIKey") or "")

        rq = (get("var", "resumeQuestion") or "").strip().lower()
        self.cb_resume.setChecked(rq in ("yes", "y", "true", "1"))
        self.cb_noninteractive.setChecked((get("var", "NonInteractive") or "2").strip() == "2")
        self.cb_split_configs.setChecked((get("settings", "SplitConfigurations") or "$false").strip().lower() == "$true")
        self.cb_include_itgid.setChecked((get("settings", "IncludeITGlueID") or "$false").strip().lower() == "$true")
        self.cb_scoped.setChecked((get("var", "ScopedMigration") or "1").strip() == "2")
        self.cb_merge_org_types.setChecked((get("var", "MergedOrganizationTypes") or "1").strip() == "2")
        self.cb_skip_integrator.setChecked((get("var", "skipIntegratorLayouts") or "$false").strip().lower() == "$true")

        def one_is_checked(name: str, default: str = "1") -> bool:
            v = (get("var", name) or default).strip()
            return v == "1"

        self.cb_companies.setChecked(one_is_checked("ImportCompanies"))
        self.cb_locations.setChecked(one_is_checked("ImportLocations"))
        self.cb_domains.setChecked(one_is_checked("ImportDomains"))
        self.cb_disable_webmon.setChecked(one_is_checked("DisableWebsiteMonitoring"))
        self.cb_configurations.setChecked(one_is_checked("ImportConfigurations"))
        self.cb_contacts.setChecked(one_is_checked("ImportContacts"))
        self.cb_flex_layouts.setChecked(one_is_checked("ImportFlexibleAssetLayouts"))
        self.cb_flex_assets.setChecked(one_is_checked("ImportFlexibleAssets"))
        self.cb_articles.setChecked(one_is_checked("ImportArticles"))
        self.cb_passwords.setChecked(one_is_checked("ImportPasswords"))

        cbd = (get("settings", "customBrandedDomain") or "n").strip().lower()
        self.cb_custom_branded.setChecked(cbd == "y")
        self.itg_custom_domains.setText(get("settings", "ITGCustomDomains") or "")
        self.itg_custom_domains.setEnabled(self.cb_custom_branded.isChecked())
        self.cb_flags.setChecked((get("var", "allowSettingFlagsAndTypes") or "True").strip().lower() in ("true", "$true", "1", "yes", "y"))

    # -----------------------------
    # Build output ps1
    # -----------------------------
    def _render_output(self) -> str:
        out = list(self.template_lines)

        def set_var(name: str, rhs: str) -> None:
            e = self.entries.get(("var", name))
            if not e:
                return
            out[e.line_no] = f"{e.indent}${name:<28} = {rhs}{e.trailing}"

        def set_setting(name: str, rhs: str) -> None:
            e = self.entries.get(("settings", name))
            if not e:
                return
            out[e.line_no] = f"{e.indent}{name:<24} = {rhs}{e.trailing}"

        def ensure_var(name: str, rhs: str) -> None:
            if ("var", name) in self.entries:
                set_var(name, rhs)
                return
            insert_at = len(out)
            for idx, line in enumerate(out):
                if line.strip() == ". .\\ITGlue-Hudu-Migration.ps1":
                    insert_at = idx
                    break
            out.insert(insert_at, f"${name:<28} = {rhs}")

        set_setting("ITGURL", ps_dq(self.itg_url.text().strip()))
        set_setting("ITGAPIEndpoint", ps_dq(self.itg_endpoint.text().strip()))
        set_setting("HuduBaseDomain", ps_dq(self.hudu_base.text().strip()))
        set_setting("InternalCompany", ps_dq(self.internal_company.text().strip()))
        if ("settings", "ConPromptPrefix") in self.entries:
            set_setting("ConPromptPrefix", ps_dq(self.config_prefix.text().strip() if self.cb_config_prefix.isChecked() else ""))
        if ("settings", "FAPromptPrefix") in self.entries:
            set_setting("FAPromptPrefix", ps_dq(self.fa_prefix.text().strip() if self.cb_fa_prefix.isChecked() else ""))

        set_var("ITGKey", ps_dq(self.itg_key.text().strip()))
        if ("var", "HuduApiKey") in self.entries:
            set_var("HuduApiKey", ps_dq(self.hudu_key.text().strip()))
        if ("var", "HuduAPIKey") in self.entries:
            set_var("HuduAPIKey", ps_dq(self.hudu_key.text().strip()))

        export_path = self.export_le.text().strip()
        for (k, n), _e in self.entries.items():
            if k == "settings" and is_export_path_setting_key(n):
                set_setting(n, ps_dq(export_path))

        if ("var", "resumeQuestion") in self.entries:
            set_var("resumeQuestion", ps_dq("yes" if self.cb_resume.isChecked() else "no"))
        if ("var", "NonInteractive") in self.entries:
            set_var("NonInteractive", "2" if self.cb_noninteractive.isChecked() else "1")

        if ("settings", "SplitConfigurations") in self.entries:
            set_setting("SplitConfigurations", "$true" if self.cb_split_configs.isChecked() else "$false")
        if ("settings", "IncludeITGlueID") in self.entries:
            set_setting("IncludeITGlueID", "$true" if self.cb_include_itgid.isChecked() else "$false")

        if ("var", "ScopedMigration") in self.entries:
            set_var("ScopedMigration", "2" if self.cb_scoped.isChecked() else "1")
        if ("var", "MergedOrganizationTypes") in self.entries:
            set_var("MergedOrganizationTypes", "2" if self.cb_merge_org_types.isChecked() else "1")
        if ("var", "skipIntegratorLayouts") in self.entries:
            set_var("skipIntegratorLayouts", "$true" if self.cb_skip_integrator.isChecked() else "$false")

        def set_1_2(name: str, checked: bool) -> None:
            if ("var", name) in self.entries:
                set_var(name, "1" if checked else "2")

        set_1_2("ImportCompanies", self.cb_companies.isChecked())
        set_1_2("ImportLocations", self.cb_locations.isChecked())
        set_1_2("ImportDomains", self.cb_domains.isChecked())
        set_1_2("DisableWebsiteMonitoring", self.cb_disable_webmon.isChecked())
        set_1_2("ImportConfigurations", self.cb_configurations.isChecked())
        set_1_2("ImportContacts", self.cb_contacts.isChecked())
        set_1_2("ImportFlexibleAssetLayouts", self.cb_flex_layouts.isChecked())
        set_1_2("ImportFlexibleAssets", self.cb_flex_assets.isChecked())
        set_1_2("ImportArticles", self.cb_articles.isChecked())
        set_1_2("ImportPasswords", self.cb_passwords.isChecked())

        if ("settings", "customBrandedDomain") in self.entries:
            set_setting("customBrandedDomain", ps_dq("y" if self.cb_custom_branded.isChecked() else "n"))
        if ("settings", "ITGCustomDomains") in self.entries and self.cb_custom_branded.isChecked():
            set_setting("ITGCustomDomains", ps_dq(self.itg_custom_domains.text().strip()))

        flags_rhs = "$true" if self.cb_flags.isChecked() else "$false"
        ensure_var("allowSettingFlagsAndTypes", flags_rhs)

        return "\n".join(out) + "\n"

    # -----------------------------
    # Validation + actions
    # -----------------------------
    def _validate(self) -> Tuple[List[str], List[str]]:
        errs: List[str] = []
        warns: List[str] = []
        export_path = normalize_user_path(self.export_le.text())
        if not export_path.exists() or not export_path.is_dir():
            errs.append(f"Export folder must exist: {export_path}")

        if len(self.hudu_key.text().strip()) != 24:
            errs.append(f"Hudu API key must be 24 characters (got {len(self.hudu_key.text().strip())}).")
        itg_len = len(self.itg_key.text().strip())
        if not (100 <= itg_len <= 105):
            warns.append(f"ITGlue API key length is unusual ({itg_len}). Expected is usually around 100-105 characters.")

        req_map = {
            "ImportCompanies": "organizations.csv",
            "ImportLocations": "locations.csv",
            "ImportDomains": "domains.csv",
            "ImportConfigurations": "configurations.csv",
            "ImportContacts": "contacts.csv",
            "ImportArticles": "documents.csv",
            "ImportPasswords": "passwords.csv",
        }
        enabled = {
            "ImportCompanies": self.cb_companies.isChecked(),
            "ImportLocations": self.cb_locations.isChecked(),
            "ImportDomains": self.cb_domains.isChecked(),
            "ImportConfigurations": self.cb_configurations.isChecked(),
            "ImportContacts": self.cb_contacts.isChecked(),
            "ImportArticles": self.cb_articles.isChecked(),
            "ImportPasswords": self.cb_passwords.isChecked(),
        }
        for k, file in req_map.items():
            if enabled.get(k):
                p = export_path / file
                if not p.exists():
                    errs.append(f"{k} enabled but missing: {p}")

        if self.cb_articles.isChecked():
            d = export_path / "documents"
            if not d.exists() or not d.is_dir():
                errs.append(f"ImportArticles enabled but missing folder: {d}")

        return errs, warns

    def _refresh(self) -> None:
        errs, warns = self._validate()
        self.output_label.setText(str(self.output_path))
        self.log_label.setText(str(self.run_log_path))
        self.report_label.setText(str(self.manual_actions_path))
        self.settings_label.setText(str(self._settings_file_path()))
        self.btn_open_report.setEnabled(self.manual_actions_path.exists())
        self.btn_open_script.setEnabled(self.output_path.exists())
        self.btn_reveal_script.setEnabled(self.output_path.parent.exists())

        if errs:
            self.status.setText("❌ Cannot generate:\n• " + "\n• ".join(errs))
        elif warns:
            self.status.setText("⚠ Ready with warnings:\n• " + "\n• ".join(warns))
        else:
            self.status.setText("✅ Ready.")

        try:
            self.preview.setPlainText(self._render_output())
        except Exception as e:
            self.preview.setPlainText(f"Preview error: {e}")

    def _generate(self, show_message: bool = True) -> bool:
        errs, warns = self._validate()
        if errs:
            if show_message:
                QMessageBox.critical(self, "Cannot generate", "\n".join(errs))
            return False
        self.output_path.write_text(self._render_output(), encoding="utf-8")
        self.btn_open_script.setEnabled(True)
        self.btn_reveal_script.setEnabled(True)
        if show_message:
            message = f"Generated:\n{self.output_path}"
            if warns:
                message += "\n\nWarnings:\n" + "\n".join(warns)
            QMessageBox.information(self, "Generated", message)
        return True

    def _settings_file_path(self) -> Path:
        return self.rr / "migration-gui-settings.json"

    def _legacy_settings_file_path(self) -> Path:
        return app_data_dir() / "saved_settings.json"

    def _collect_current_settings(self) -> Dict[str, object]:
        mapping = {
            "itg_url": self.itg_url.text().strip(),
            "itg_endpoint": self.itg_endpoint.text().strip(),
            "hudu_base": self.hudu_base.text().strip(),
            "internal_company": self.internal_company.text().strip(),
            "config_prefix": self.config_prefix.text().strip(),
            "fa_prefix": self.fa_prefix.text().strip(),
            "itg_key": self.itg_key.text().strip(),
            "hudu_key": self.hudu_key.text().strip(),
            "export_path": self.export_le.text().strip(),
            "custom_domains": self.itg_custom_domains.text().strip(),
        }
        checkboxes = {
            "resume": self.cb_resume,
            "noninteractive": self.cb_noninteractive,
            "split_configs": self.cb_split_configs,
            "include_itgid": self.cb_include_itgid,
            "scoped": self.cb_scoped,
            "merge_org_types": self.cb_merge_org_types,
            "skip_integrator": self.cb_skip_integrator,
            "apply_flags": self.cb_flags,
            "companies": self.cb_companies,
            "locations": self.cb_locations,
            "domains": self.cb_domains,
            "disable_webmon": self.cb_disable_webmon,
            "configurations": self.cb_configurations,
            "contacts": self.cb_contacts,
            "flex_layouts": self.cb_flex_layouts,
            "flex_assets": self.cb_flex_assets,
            "articles": self.cb_articles,
            "passwords": self.cb_passwords,
            "custom_branded": self.cb_custom_branded,
            "config_prefix_enabled": self.cb_config_prefix,
            "fa_prefix_enabled": self.cb_fa_prefix,
        }
        for key, cb in checkboxes.items():
            mapping[key] = cb.isChecked()
        return mapping

    def _apply_saved_settings(self) -> None:
        path = self._settings_file_path()
        if not path.exists():
            legacy = self._legacy_settings_file_path()
            if legacy.exists():
                path = legacy
            else:
                return
        if not path.exists():
            return
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return

        field_map = {
            "itg_url": self.itg_url,
            "itg_endpoint": self.itg_endpoint,
            "hudu_base": self.hudu_base,
            "internal_company": self.internal_company,
            "config_prefix": self.config_prefix,
            "fa_prefix": self.fa_prefix,
            "export_path": self.export_le,
            "custom_domains": self.itg_custom_domains,
            "itg_key": self.itg_key,
            "hudu_key": self.hudu_key,
        }
        for key, widget in field_map.items():
            value = data.get(key)
            if isinstance(widget, QLineEdit) and isinstance(value, str):
                widget.setText(value)

        checkbox_map = {
            "resume": self.cb_resume,
            "noninteractive": self.cb_noninteractive,
            "split_configs": self.cb_split_configs,
            "include_itgid": self.cb_include_itgid,
            "scoped": self.cb_scoped,
            "merge_org_types": self.cb_merge_org_types,
            "skip_integrator": self.cb_skip_integrator,
            "apply_flags": self.cb_flags,
            "companies": self.cb_companies,
            "locations": self.cb_locations,
            "domains": self.cb_domains,
            "disable_webmon": self.cb_disable_webmon,
            "configurations": self.cb_configurations,
            "contacts": self.cb_contacts,
            "flex_layouts": self.cb_flex_layouts,
            "flex_assets": self.cb_flex_assets,
            "articles": self.cb_articles,
            "passwords": self.cb_passwords,
            "custom_branded": self.cb_custom_branded,
            "config_prefix_enabled": self.cb_config_prefix,
            "fa_prefix_enabled": self.cb_fa_prefix,
        }
        for key, widget in checkbox_map.items():
            if isinstance(data.get(key), bool):
                widget.setChecked(data[key])

        self._refresh()

    def _save_settings(self) -> None:
        path = self._settings_file_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            path.write_text(json.dumps(self._collect_current_settings(), indent=2), encoding="utf-8")
        except Exception as exc:
            QMessageBox.critical(self, "Save failed", f"Could not save settings: {exc}")
            return
        QMessageBox.information(self, "Saved", f"Settings saved to {path}")

    def _embedded_run_blockers(self) -> List[str]:
        blockers: List[str] = []
        if not self.cb_noninteractive.isChecked():
            blockers.append("Enable Non-interactive mode for in-app runs.")
        if self.cb_scoped.isChecked():
            blockers.append("Scoped migration still requires interactive company selection in PowerShell.")
        if self.cb_merge_org_types.isChecked():
            blockers.append("Merge selected org types still requires interactive selection in PowerShell.")
        return blockers

    def _confirm_readme_acknowledgement(self) -> bool:
        box = QMessageBox(self)
        box.setWindowTitle("Confirm README Review")
        box.setIcon(QMessageBox.Icon.Question)
        box.setText("Have you read the README and understand the migration limitations?")
        box.setInformativeText("Reviewing it first is strongly recommended before starting the migration.")
        open_btn = box.addButton("Open README", QMessageBox.ButtonRole.ActionRole)
        yes_btn = box.addButton("Yes", QMessageBox.ButtonRole.YesRole)
        no_btn = box.addButton("No", QMessageBox.ButtonRole.NoRole)
        box.exec()

        clicked = box.clickedButton()
        if clicked == open_btn:
            os.startfile(self._github_readme_url())
            return self._confirm_readme_acknowledgement()
        if clicked == yes_btn:
            return True
        if clicked == no_btn:
            return False
        return False

    def _previous_run_markers(self) -> List[Path]:
        debug_root = self.rr / "debug"
        return [
            self.run_log_path,
            self.manual_actions_path,
            debug_root / "logs",
            debug_root / "settings",
            debug_root / "errors",
        ]

    def _has_previous_run_state(self) -> bool:
        for path in self._previous_run_markers():
            try:
                if path.is_file():
                    if path.stat().st_size > 0:
                        return True
                elif path.is_dir() and any(path.iterdir()):
                    return True
            except OSError:
                continue
        return False

    def _confirm_resume_run(self) -> bool:
        if not self._has_previous_run_state():
            return True
        box = QMessageBox(self)
        box.setWindowTitle("Previous run detected")
        box.setIcon(QMessageBox.Icon.Warning)
        box.setText("Previous run data was found. The migration run will resume from the last successful section.")
        box.setInformativeText("Continuing will not restart from the beginning.")
        yes_btn = box.addButton("Yes", QMessageBox.ButtonRole.YesRole)
        no_btn = box.addButton("No", QMessageBox.ButtonRole.NoRole)
        help_btn = box.addButton("Help", QMessageBox.ButtonRole.HelpRole)
        box.setDefaultButton(no_btn)
        box.exec()
        clicked = box.clickedButton()
        if clicked == yes_btn:
            return True
        if clicked == help_btn:
            self._show_previous_run_help()
            return self._confirm_resume_run()
        if clicked == no_btn:
            return False
        return False

    def _show_previous_run_help(self) -> None:
        paths = self._previous_run_markers()
        box = QMessageBox(self)
        box.setWindowTitle("Clearing previous run state")
        box.setIcon(QMessageBox.Icon.Information)
        box.setText("Delete the files below to force a fresh migration run:")
        box.setInformativeText("\n".join(f"• {str(p)}" for p in paths))
        delete_btn = box.addButton("Delete previous run files and logs", QMessageBox.ButtonRole.DestructiveRole)
        box.addButton("OK", QMessageBox.ButtonRole.NoRole)
        box.exec()
        if box.clickedButton() == delete_btn:
            confirm = QMessageBox.question(
                self,
                "Confirm deletion",
                "Are you sure? This is permanent and will remove all previous run logs/settings.",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            if confirm == QMessageBox.StandardButton.Yes:
                self._clear_previous_run_files()

    def _clear_previous_run_files(self) -> None:
        for path in (self.run_log_path, self.manual_actions_path):
            try:
                if path.exists():
                    path.unlink()
            except OSError:
                continue
        debug_root = self.rr / "debug"
        for sub in ("logs", "settings", "errors"):
            folder = debug_root / sub
            if folder.exists():
                shutil.rmtree(folder, ignore_errors=True)
            folder.mkdir(parents=True, exist_ok=True)
        QMessageBox.information(self, "Previous run cleared", "Previous run files and logs were deleted.")
        self._refresh()
        return clicked == yes_btn

    def _select_output_tab(self) -> None:
        for i in range(self.tabs.count()):
            if self.tabs.tabText(i) == "Run Output":
                self.tabs.setCurrentIndex(i)
                return

    def _set_run_controls(self, running: bool) -> None:
        self.btn_run.setEnabled(not running)
        self.btn_run_console.setEnabled(not running)
        self.btn_stop_run.setEnabled(running)
        self.btn_save_settings.setEnabled(not running)
        self.btn_open_script.setEnabled(self.output_path.exists())
        self.btn_reveal_script.setEnabled(self.output_path.parent.exists())

    def _prepare_run_output(self, mode: str, detail: str) -> None:
        self._run_mode = mode
        self._tail_timer.stop()
        self._tail_pos = 0
        self._tail_buffer = ""
        self._run_buffer = ""
        self._select_output_tab()
        self.output_view.clear()
        self.run_mode_label.setText(f"Run Mode: {mode}")
        self.run_stage_label.setText("Stage: Preparing migration")
        self.run_detail_label.setText(f"Current item: {detail}")
        self.run_progress.setValue(2)
        self.btn_open_log.setEnabled(True)
        self.btn_open_report.setEnabled(False)

    def _set_run_stage(self, label: str, progress: int, detail: Optional[str] = None) -> None:
        self.run_stage_label.setText(f"Stage: {label}")
        if progress >= self.run_progress.value():
            self.run_progress.setValue(min(progress, 100))
        if detail:
            self.run_detail_label.setText(f"Current item: {detail}")

    def _append_to_run_log(self, line: str) -> None:
        try:
            with self.run_log_path.open("a", encoding="utf-8") as f:
                f.write(line + "\n")
        except Exception:
            pass

    def _ingest_output_line(self, line: str, *, write_log: bool) -> None:
        clean = clean_console_line(line)
        if write_log:
            self._append_to_run_log(clean)
        self.output_view.append(output_line_html(clean))
        self._update_progress_from_line(clean)

    def _consume_output_chunk(self, chunk: str, *, buffer_name: str, write_log: bool) -> None:
        pending = getattr(self, buffer_name) + chunk.replace("\r\n", "\n").replace("\r", "\n")
        while "\n" in pending:
            line, pending = pending.split("\n", 1)
            self._ingest_output_line(line, write_log=write_log)
        setattr(self, buffer_name, pending)

    def _flush_output_buffer(self, *, buffer_name: str, write_log: bool) -> None:
        pending = getattr(self, buffer_name)
        if pending:
            self._ingest_output_line(pending, write_log=write_log)
            setattr(self, buffer_name, "")

    def _update_progress_from_line(self, line: str) -> None:
        text = line.strip()
        if not text:
            return

        wrapup = re.search(r"wrapup\s+(\d+)/9", text, re.IGNORECASE)
        if wrapup:
            step = int(wrapup.group(1))
            progress = min(99, 95 + round(step * 5 / 9))
            self._set_run_stage(f"Wrap-up ({step}/9)", progress, text)
            return

        for pattern, label, progress in RUN_STAGE_RULES:
            if pattern.search(text):
                self._set_run_stage(label, progress, text)
                if progress >= 100 and self.manual_actions_path.exists():
                    self.btn_open_report.setEnabled(True)
                break

        if text.startswith("Starting "):
            self.run_detail_label.setText(f"Current item: {text[9:]}")
        elif text.startswith("Migrating "):
            self.run_detail_label.setText(f"Current item: {text}")
        elif text.startswith("Loading ") or text.startswith("Fetching "):
            self.run_detail_label.setText(f"Current item: {text}")

    def _embedded_pwsh_command(self) -> str:
        return (
            "$ProgressPreference = 'SilentlyContinue'; "
            "$InformationPreference = 'Continue'; "
            "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); "
            "$OutputEncoding = [Console]::OutputEncoding; "
            f"Set-Location -LiteralPath {ps_single_quote(str(self.rr))}; "
            f"& {ps_single_quote(str(self.output_path))} *>&1"
        )

    def _start_migration(self) -> None:
        pwsh = detect_pwsh()
        if not pwsh:
            QMessageBox.critical(self, "Missing pwsh", "PowerShell 7 (pwsh) was not found on PATH.")
            return
        if self._run_process and self._run_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Already running", "An in-app migration is already running.")
            return
        if not self._confirm_readme_acknowledgement():
            return
        if not self._confirm_resume_run():
            return

        blockers = self._embedded_run_blockers()
        if blockers:
            QMessageBox.information(
                self,
                "Use PowerShell fallback for this configuration",
                "The embedded runner is best for unattended migrations.\n\n" + "\n".join(f"• {b}" for b in blockers),
            )
            return

        if not self._generate(show_message=False):
            return

        ts = time.strftime("%Y-%m-%d %H:%M:%S")
        self.run_log_path.write_text(f"=== Run started {ts} ===\n", encoding="utf-8")
        self._prepare_run_output("In-App PowerShell", "Launching migration script")
        self._set_run_controls(True)
        self._append_to_run_log(f"=== Embedded run launched from GUI at {ts} ===")

        proc = QProcess(self)
        proc.setWorkingDirectory(str(self.rr))
        proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        proc.readyReadStandardOutput.connect(self._on_run_ready_read)
        proc.finished.connect(self._on_run_finished)
        proc.errorOccurred.connect(self._on_run_error)
        proc.start(
            pwsh,
            [
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                self._embedded_pwsh_command(),
            ],
        )
        self._run_process = proc
        self.output_view.append(output_line_html(f"Launching {self.output_path.name} inside the app..."))

        if not proc.waitForStarted(5000):
            self._set_run_controls(False)
            self._run_process = None
            QMessageBox.critical(self, "Launch failed", "The migration process could not be started.")
            return

    def _on_run_ready_read(self) -> None:
        if not self._run_process:
            return
        chunk = bytes(self._run_process.readAllStandardOutput()).decode("utf-8", errors="replace")
        self._consume_output_chunk(chunk, buffer_name="_run_buffer", write_log=True)

    def _on_run_finished(self, exit_code: int, _exit_status: QProcess.ExitStatus) -> None:
        self._flush_output_buffer(buffer_name="_run_buffer", write_log=True)
        self._set_run_controls(False)
        self._run_process = None

        if exit_code == 0:
            self.run_mode_label.setText("Run Mode: In-App PowerShell (completed)")
            self._set_run_stage("Migration finished", 100, "PowerShell process exited cleanly.")
        else:
            self.run_mode_label.setText("Run Mode: In-App PowerShell (stopped)")
            self.run_detail_label.setText(f"Current item: PowerShell exited with code {exit_code}. Review the output and log.")

        self.btn_open_report.setEnabled(self.manual_actions_path.exists())

    def _on_run_error(self, process_error: QProcess.ProcessError) -> None:
        self.run_detail_label.setText(f"Current item: Embedded PowerShell error: {process_error}")

    def _stop_migration(self) -> None:
        if not self._run_process or self._run_process.state() == QProcess.ProcessState.NotRunning:
            return
        result = QMessageBox.question(
            self,
            "Stop migration",
            "Stop the in-app migration process? You can usually resume later if logs were written.",
        )
        if result != QMessageBox.Yes:
            return
        self._append_to_run_log("=== Embedded run stopped by user ===")
        self._run_process.kill()

    def _run_in_console(self) -> None:
        pwsh = detect_pwsh()
        if not pwsh:
            QMessageBox.critical(self, "Missing pwsh", "PowerShell 7 (pwsh) was not found on PATH.")
            return
        if self._run_process and self._run_process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self, "Already running", "Stop the in-app migration before launching PowerShell fallback.")
            return
        if not self._generate(show_message=False):
            return

        ts = time.strftime("%Y-%m-%d %H:%M:%S")
        self.run_log_path.write_text(f"=== Console run started {ts} ===\n", encoding="utf-8")
        self._prepare_run_output("External PowerShell", "Waiting for output from the visible PowerShell window")
        self.run_detail_label.setText("Current item: Use this mode for scoped or other interactive flows.")
        self._start_tailing_log()

        ps_command = (
            "$ProgressPreference = 'SilentlyContinue'; "
            "$InformationPreference = 'Continue'; "
            f"Set-Location -LiteralPath {ps_single_quote(str(self.rr))}; "
            f"& {ps_single_quote(str(self.output_path))} *>&1 | Tee-Object -FilePath {ps_single_quote(str(self.run_log_path))} -Append"
        )
        subprocess.Popen(
            [
                pwsh,
                "-NoExit",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                ps_command,
            ],
            cwd=str(self.rr),
        )

    def _open_manual_actions_report(self) -> None:
        if not self.manual_actions_path.exists():
            QMessageBox.warning(self, "Missing report", f"No report found:\n{self.manual_actions_path}")
            return
        os.startfile(str(self.manual_actions_path))  # noqa

    def _open_run_script(self) -> None:
        if not self.output_path.exists():
            QMessageBox.warning(self, "Missing script", f"No script found:\n{self.output_path}")
            return
        os.startfile(str(self.output_path))  # noqa

    def _reveal_run_script(self) -> None:
        folder = self.output_path.parent
        if not folder.exists():
            QMessageBox.warning(self, "Missing folder", f"No folder found:\n{folder}")
            return
        os.startfile(str(folder))  # noqa

    def _open_run_log(self) -> None:
        if not self.run_log_path.exists():
            QMessageBox.warning(self, "Missing log", f"No log found:\n{self.run_log_path}")
            return
        os.startfile(str(self.run_log_path))  # noqa

    def _browse_export(self) -> None:
        d = QFileDialog.getExistingDirectory(self, "Select export folder", self.export_le.text())
        if d:
            self.export_le.setText(d)

    # -----------------------------
    # Log tailing (Run Output)
    # -----------------------------
    def _start_tailing_log(self) -> None:
        self._tail_pos = 0
        self._tail_buffer = ""
        self._select_output_tab()
        self.output_view.clear()
        self._tail_timer.start()

    def _tail_log_tick(self) -> None:
        if not self.run_log_path.exists():
            return
        try:
            with self.run_log_path.open("r", encoding="utf-8", errors="replace") as f:
                f.seek(self._tail_pos)
                chunk = f.read()
                self._tail_pos = f.tell()
        except Exception:
            return
        if chunk:
            self._consume_output_chunk(chunk, buffer_name="_tail_buffer", write_log=False)


def main() -> int:
    app = QApplication(sys.argv)
    icon_path = app_icon_candidate(repo_root_candidate())
    if icon_path:
        app.setWindowIcon(QIcon(str(icon_path)))
    win = MainWindow()
    win.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
