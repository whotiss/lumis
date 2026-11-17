"""Save one secret in Google Secret Manager without it appearing on screen, in a file or in the shell history.

    python deploy/set_secret.py lumis-database-url         # asks for the value (typing is hidden)
    python deploy/set_secret.py lumis-anthropic-key
    python deploy/set_secret.py lumis-jwt-secret --generate   # makes a long random value itself
    python deploy/set_secret.py lumis-database-url --from-env-file ../.env.local --env-key DATABASE_URL
                                                              # takes the value from a file such as the one
                                                              # `neon init` writes, without showing it

It creates the secret if it does not exist yet and adds the value as a new version. Spaces and line breaks
around the value are removed. Needs the gcloud CLI, signed in, with the project already selected.
"""
import argparse
import getpass
import secrets
import shutil
import subprocess
import sys


def gcloud(*args, value: bytes | None = None) -> subprocess.CompletedProcess:
    exe = shutil.which("gcloud") or shutil.which("gcloud.cmd")
    if not exe:
        sys.exit("gcloud was not found. Install the Google Cloud CLI, then open a new terminal.")
    return subprocess.run([exe, *args], input=value, capture_output=True)


def read_env_value(path: str, key: str) -> str:
    """The value of KEY=value in a .env file (quotes and an 'export ' prefix allowed). Never printed."""
    try:
        lines = open(path, encoding="utf-8-sig").read().splitlines()
    except OSError as exc:
        sys.exit(f"Could not read {path}: {exc.strerror}")
    for line in lines:
        line = line.strip()
        if line.startswith("export "):
            line = line[len("export "):].lstrip()
        name, sep, value = line.partition("=")
        if sep and name.strip() == key:
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1]
            if not value:
                sys.exit(f"{key} is empty in {path}.")
            return value
    sys.exit(f"{key} was not found in {path}.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name", help="secret name, for example lumis-database-url")
    ap.add_argument("--generate", action="store_true", help="generate a random value instead of asking for one")
    ap.add_argument("--from-env-file", help="read the value from this .env-style file instead of asking")
    ap.add_argument("--env-key", default="DATABASE_URL", help="the variable to read from --from-env-file")
    args = ap.parse_args()

    if args.generate:
        value = secrets.token_urlsafe(48)
    elif args.from_env_file:
        value = read_env_value(args.from_env_file, args.env_key)
    else:
        value = getpass.getpass(f"Paste the value for {args.name} (it stays hidden), then press Enter: ").strip()
        if not value:
            sys.exit("Nothing was entered, so nothing was saved.")
        if any(c in value for c in "\r\n"):
            sys.exit("The value contains a line break. Paste it as a single line.")

    if gcloud("secrets", "describe", args.name).returncode != 0:
        r = gcloud("secrets", "create", args.name, "--replication-policy", "automatic")
        if r.returncode != 0:
            sys.exit("Could not create the secret:\n" + r.stderr.decode(errors="replace"))
        print(f"Created secret {args.name}.")
    r = gcloud("secrets", "versions", "add", args.name, "--data-file=-", value=value.encode())
    if r.returncode != 0:
        sys.exit("Could not save the value:\n" + r.stderr.decode(errors="replace"))
    print(f"Saved a new version of {args.name} ({len(value)} characters). The value itself is not shown.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
