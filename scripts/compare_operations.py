"""Compare validated read-only snapshots without mistaking hover for a reroll."""
import argparse
import json
from pathlib import Path
from inspect_operations import decode_capture


def compare_captures(before_capture, after_capture):
    before, after = decode_capture(before_capture), decode_capture(after_capture)
    if before['planet_index'] != after['planet_index']:
        raise ValueError('Compare the same planet before and after the UI transition')
    # Snapshot positions are stable enough for exact equality, but not an identity
    # for changed operations. Report equality only; do not pair by operation ID.
    def generation_content(snapshot):
        return [{key: op[key] for key in ('row', 'operation_id', 'difficulty', 'seed',
                                          'template_index', 'faction')} |
                {'missions': [{key: m[key] for key in
                               ('row', 'slot', 'native_type', 'seed', 'level_index', 'kind')}
                              for m in op['missions']]}
                for op in snapshot['operations']]
    return dict(
        same_session=before_capture['session'] == after_capture['session'],
        planet_index=before['planet_index'],
        highlighted_before=before['highlighted_operation'],
        highlighted_after=after['highlighted_operation'],
        campaign_seed_changed=before['campaign_seed'] != after['campaign_seed'],
        generation_content_changed=generation_content(before) != generation_content(after),
        operation_records_changed=before['operations'] != after['operations'],
        before_operations=len(before['operations']), after_operations=len(after['operations']),
        interpretation='Content comparison only; cannot prove a native generator was or was not invoked',
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    args = parser.parse_args()
    captures = [json.loads(p.read_text(encoding='utf-8')) for p in (args.before, args.after)]
    print(json.dumps(compare_captures(*captures), indent=2))


if __name__ == '__main__':
    main()
