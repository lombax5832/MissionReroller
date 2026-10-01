"""Print the CHANGELOG.md section for one version: Markdown bullets for the
GitHub release, or with --plain one line of plain text per change for the
Nexus Mods changelog, which renders no Markdown. Fails when the tag is not a
version or CHANGELOG.md has no section for it.

    python -B scripts/release_notes.py v0.27.0 [--plain]
"""
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / 'CHANGELOG.md'
SECTION = re.compile(r'^## v(\d+\.\d+\.\d+)\b')


def changes(version, text):
    """Each `- ` bullet of the `## v<version> <title>` section as one line,
    its wrapped continuation lines joined on, marker removed."""
    items, current = [], False
    for line in text.splitlines():
        if line.startswith('## '):
            section = SECTION.match(line)
            current = bool(section) and section.group(1) == version
        elif current and line.startswith('- '):
            items.append(line[2:].strip())
        elif current and line.strip():
            if not items:
                raise SystemExit(f'CHANGELOG.md v{version}: text before the first "- " bullet: {line}')
            items[-1] += ' ' + line.strip()
    return items


def entries(version, text):
    return '\n'.join('- ' + item for item in changes(version, text))


def plain(version, text):
    return '\n'.join(changes(version, text))


def notes(version, plain_text=False):
    text = CHANGELOG.read_text(encoding='utf-8')
    return plain(version, text) if plain_text else entries(version, text)


def main(tag, *flags):
    import build
    version = build.release_version(tag)
    text = notes(version, '--plain' in flags)
    if not text:
        sys.exit(f'CHANGELOG.md has no section for v{version}')
    print(text)


if __name__ == '__main__':
    sys.path.insert(0, str(ROOT / 'scripts'))
    main(*sys.argv[1:])
