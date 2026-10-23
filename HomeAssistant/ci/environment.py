# SPDX-License-Identifier: MPL-2.0
"""Install and verify the isolated HA contract-test environment, never a live HA."""
from importlib import metadata
import subprocess
import sys

HA_VERSION = "2026.10.0"
SEGNO_VERSION = "1.6.6"
OVERRIDES = {
    "Pillow==12.3.0": "Pillow==13.0.0",
    "uv==0.12.23": "uv==0.13.4",
}
EXPECTED_CONFLICTS = {
    f"homeassistant {HA_VERSION} has requirement pillow==12.3.0, but you have pillow 13.0.0.",
    f"homeassistant {HA_VERSION} has requirement uv==0.12.23, but you have uv 0.13.4.",
}


def patched_requirements(requirements):
    """Fail closed if upstream changes either exact pin; preserve everything else."""
    for requirement in OVERRIDES:
        if requirements.count(requirement) != 1:
            raise RuntimeError(f"Review changed HA test dependency: {requirement}")
    return [OVERRIDES.get(requirement, requirement) for requirement in requirements]


def verify_pip_check(result):
    lines = [line.strip().lower() for line in result.stdout.splitlines() if line.strip()]
    if (result.returncode != 1 or result.stderr.strip()
            or len(lines) != len(EXPECTED_CONFLICTS) or set(lines) != EXPECTED_CONFLICTS):
        raise RuntimeError(f"Unexpected dependency check result:\n{result.stdout}\n{result.stderr}")


def require_virtualenv():
    if sys.prefix == sys.base_prefix:
        raise RuntimeError("Use an isolated test venv; never run this against installed Home Assistant.")


def install():
    require_virtualenv()
    # Install HA's unmodified wheel without fetching its vulnerable exact pins.
    subprocess.run([sys.executable, "-m", "pip", "install", "--no-deps",
                    f"homeassistant=={HA_VERSION}"], check=True)
    requirements = patched_requirements(metadata.requires("homeassistant"))
    subprocess.run([sys.executable, "-m", "pip", "install", "--only-binary=Pillow,uv",
                    *requirements, f"segno=={SEGNO_VERSION}"], check=True)
    verify()


def verify():
    require_virtualenv()
    for package, expected in {"homeassistant": HA_VERSION, "Pillow": "13.0.0",
                              "uv": "0.13.4", "segno": SEGNO_VERSION}.items():
        actual = metadata.version(package)
        print(f"Resolved {package}=={actual}", flush=True)
        if actual != expected:
            raise RuntimeError(f"Expected {package}=={expected}; got {actual}")
    patched_requirements(metadata.requires("homeassistant"))
    result = subprocess.run([sys.executable, "-m", "pip", "check"],
                            text=True, capture_output=True)
    verify_pip_check(result)
    print(result.stdout, end="")
    print("Only the two documented HA test-only pin exceptions remain; no other conflicts.")
    subprocess.run([sys.executable, "-m", "uv", "--version"], check=True)
    # Exercise the installed wheel, including the codec covered by the advisory.
    from io import BytesIO
    from PIL import Image, features
    print(f"Pillow JPEG 2000 codec: {features.version_codec('jpg_2000')}")
    for image_format in ("PNG", "JPEG2000"):
        buffer = BytesIO()
        Image.new("RGB", (8, 8), "red").save(buffer, format=image_format)
        buffer.seek(0)
        with Image.open(buffer) as image:
            image.load()
            assert image.size == (8, 8)
        print(f"Pillow {image_format} encode/decode passed")


if __name__ == "__main__":
    if sys.argv[1:] == ["install"]:
        install()
    elif sys.argv[1:] == ["verify"]:
        verify()
    else:
        raise SystemExit("Usage: environment.py install|verify (isolated CI venv only)")
