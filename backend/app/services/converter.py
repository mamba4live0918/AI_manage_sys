import os
import subprocess
import tempfile
import shutil
from pathlib import Path

# Common install paths for LibreOffice on different platforms
_SOFFICE_CANDIDATES = [
    r"C:\Program Files\LibreOffice\program\soffice.exe",
    r"C:\Program Files (x86)\LibreOffice\program\soffice.exe",
    "/usr/bin/soffice",
    "/usr/local/bin/soffice",
]


def _find_soffice() -> str:
    for path in _SOFFICE_CANDIDATES:
        if Path(path).exists():
            return path
    # Fall back to PATH lookup
    for name in ("soffice", "libreoffice"):
        found = shutil.which(name)
        if found:
            return found
    raise FileNotFoundError(
        "LibreOffice not found. Install it: winget install LibreOffice.LibreOffice"
    )


async def convert_to_pdf(input_bytes: bytes, filename: str) -> bytes:
    soffice = _find_soffice()

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = Path(tmpdir) / filename
        input_path.write_bytes(input_bytes)

        subprocess.run(
            [soffice, "--headless", "--convert-to", "pdf", "--outdir", tmpdir, str(input_path)],
            check=True,
            capture_output=True,
            timeout=30,
        )

        pdf_name = input_path.stem + ".pdf"
        pdf_path = Path(tmpdir) / pdf_name
        if not pdf_path.exists():
            raise RuntimeError(f"PDF conversion failed: output not found at {pdf_path}")

        return pdf_path.read_bytes()
