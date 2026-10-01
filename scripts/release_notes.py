"""Print the CHANGELOG.md section for one version, for the GitHub release
and the Nexus Mods changelog. Fails when the tag is not a version or
CHANGELOG.md has no section for it.

    python -B scripts/release_notes.py v0.27.0
"""
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / 'CHANGELOG.md'
SECTION = re.compile(r'^## v(\d+\.\d+\.\d+)\b')


def entries(version, text):
    """The body of the `## v<version> <title>` section, heading removed."""
    lines, current = [], False
    for line in text.splitlines():
        if line.startswith('## '):
            section = SECTION.match(line)
            current = bool(section) and section.group(1) == version
            continue
        if current:
            lines.append(line)
    return '\n'.join(lines).strip()


def notes(version):
    return entries(version, CHANGELOG.read_text(encoding='utf-8'))


def main(tag):
    import build
    version = build.release_version(tag)
    text = notes(version)
    if not text:
        sys.exit(f'CHANGELOG.md has no section for v{version}')
    print(text)


if __name__ == '__main__':
    sys.path.insert(0, str(ROOT / 'scripts'))
    main(sys.argv[1])
