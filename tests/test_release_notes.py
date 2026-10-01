"""CHANGELOG.md is what players read on Nexus Mods and GitHub.

Checks scripts/release_notes.py picks out one version's section and joins
wrapped bullets, and fails on development detail in the changelog (code
spans, file names, links, addresses and log tags belong in docs/HISTORY.md)
and on Markdown emphasis, which Nexus Mods shows as literal characters.
"""
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import release_notes

DEVELOPER_TEXT = {
    'code span': re.compile(r'`'),
    'link': re.compile(r'\]\('),
    'file name': re.compile(r'\b[\w/]+\.(?:lua|py|md|yml|dl_bin)\b|\b(?:src|docs|scripts|tests)/'),
    'address': re.compile(r'\b0x[0-9a-fA-F]+\b|\b[0-9a-f]{6,}\b'),
    'log tag': re.compile(r'\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b'),
    'emphasis': re.compile(r'[*#]|(?<!\w)_|_(?!\w)'),
}


def test_entries():
    text = '\n'.join([
        '# Changelog', 'Intro.', '',
        '## v1.2.0 Second', '', '- Two.', '',
        '## v1.1.0 First', '', '- One,', '  wrapped.', '- Also one.', '',
        '## Unreleased', '- Later.',
    ])
    assert release_notes.entries('1.2.0', text) == '- Two.'
    assert release_notes.entries('1.1.0', text) == '- One, wrapped.\n- Also one.'
    assert release_notes.plain('1.1.0', text) == 'One, wrapped.\nAlso one.'
    assert release_notes.entries('1.0.0', text) == ''
    try:
        release_notes.changes('1.0.0', '## v1.0.0 Prose\nNot a bullet.')
    except SystemExit:
        pass
    else:
        raise AssertionError('text before the first bullet was accepted')


def test_changelog_is_for_players():
    text = release_notes.CHANGELOG.read_text(encoding='utf-8')
    versions = [m.group(1) for m in map(release_notes.SECTION.match, text.splitlines()) if m]
    assert versions, 'CHANGELOG.md has no version sections'
    assert len(versions) == len(set(versions)), 'a version appears twice in CHANGELOG.md'
    for version in versions:
        notes = release_notes.plain(version, text)
        assert notes, f'v{version} has an empty section'
        for line in notes.splitlines():
            for what, pattern in DEVELOPER_TEXT.items():
                assert not pattern.search(line), f'v{version} {what}: {line}'


if __name__ == '__main__':
    test_entries()
    test_changelog_is_for_players()
    print('test_release_notes: passed')
