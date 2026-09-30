"""Print the docs/HISTORY.md entries for one version, for the GitHub release
and the Nexus Mods changelog. Fails when the tag and build.VERSION disagree.

    python -B scripts/release_notes.py v0.24.0
"""
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
HEADING = re.compile(r'^\*\*.*?\bv(\d+\.\d+\.\d+)\b')
STATUS = re.compile(r'^\*\*(?:Not yet validated in game|Validated in game|Next in-game test):\s*')


def entries(version, text):
    """Every entry whose bold heading names this version, status prefix removed."""
    blocks, current = [], None
    for line in text.splitlines():
        heading = HEADING.match(line)
        if heading:
            current = [] if heading.group(1) == version else None
            if current is not None:
                blocks.append(current)
                line = STATUS.sub('**', line)
        if current is not None:
            current.append(line)
    return '\n\n'.join('\n'.join(block).strip() for block in blocks)


def main(tag):
    import build
    version = tag[1:] if tag.startswith('v') else tag
    if version != build.VERSION:
        sys.exit(f'tag {tag} does not match VERSION {build.VERSION} in scripts/build.py')
    notes = entries(version, (ROOT / 'docs' / 'HISTORY.md').read_text(encoding='utf-8'))
    if not notes:
        sys.exit(f'docs/HISTORY.md has no entry for v{version}')
    print(notes)


if __name__ == '__main__':
    sys.path.insert(0, str(ROOT / 'scripts'))
    main(sys.argv[1])
