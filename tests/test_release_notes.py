"""CHANGELOG.md is what players read on Nexus Mods and GitHub.

Checks scripts/release_notes.py picks out one version's section, and fails
on development detail in the changelog: code spans, file names, links,
addresses and log tags belong in docs/HISTORY.md.
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
}


def test_entries():
    text = '\n'.join([
        '# Changelog', 'Intro.', '',
        '## v1.2.0 Second', '', '- Two.', '',
        '## v1.1.0 First', '', '- One.', '- Also one.', '',
        '## Unreleased', '- Later.',
    ])
    assert release_notes.entries('1.2.0', text) == '- Two.'
    assert release_notes.entries('1.1.0', text) == '- One.\n- Also one.'
    assert release_notes.entries('1.0.0', text) == ''


def test_changelog_is_for_players():
    text = release_notes.CHANGELOG.read_text(encoding='utf-8')
    versions = [m.group(1) for m in map(release_notes.SECTION.match, text.splitlines()) if m]
    assert versions, 'CHANGELOG.md has no version sections'
    assert len(versions) == len(set(versions)), 'a version appears twice in CHANGELOG.md'
    for version in versions:
        notes = release_notes.entries(version, text)
        assert notes, f'v{version} has an empty section'
        for line in notes.splitlines():
            for what, pattern in DEVELOPER_TEXT.items():
                assert not pattern.search(line), f'v{version} {what}: {line}'


if __name__ == '__main__':
    test_entries()
    test_changelog_is_for_players()
    print('test_release_notes: passed')
