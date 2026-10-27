"""Build a deterministic source-only ZIP; boto3 is supplied by the Lambda runtime."""

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]


def main():
    info = ZipInfo("ami.py", date_time=(2020, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    info.compress_type = ZIP_DEFLATED
    with ZipFile(ROOT / "ami.zip", "w") as archive:
        archive.writestr(info, (ROOT / "ami.py").read_bytes())


if __name__ == "__main__":
    main()
