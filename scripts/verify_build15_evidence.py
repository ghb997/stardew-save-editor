"""Check build 15 split regression evidence without relabeling the failed full run.

Requires this repository's Git history. With --artifact-root, also compare each
reported result against the original downloaded XCTest log. Does not run tests.
"""
from collections import Counter
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
REPAIR = 'RepairEditorUITests'


def read(path):
    return json.loads(path.read_text('utf-8'))


def git(*parts):
    return subprocess.check_output(['git', '-c', 'safe.directory=' + ROOT.as_posix(),
                                   '-C', str(ROOT), *parts])


def declared(commit):
    result = set()
    for path in git('ls-tree', '-r', '--name-only', commit).decode().splitlines():
        if path.endswith('.swift') and path.startswith(('PelicanSaveEditorTests/', 'PelicanSaveEditorUITests/')):
            source = git('show', commit + ':' + path).decode('utf-8')
            result.update((Path(path).stem, method)
                          for method in re.findall(r'\bfunc\s+(test\w+)\s*\(', source))
    return result


def key(test):
    return test['class'], test['method']


def verify(artifact_root=None, require_visual=True):
    folder = ROOT / 'validation'
    build = read(folder / 'build15-device-build.json')
    assert build['status'] == 'succeeded'
    reports = {name: read(folder / ('build15-tests-' + name + '.json'))
               for name in ('iphone-full', 'iphone-repair', 'mini', 'large')}
    full, repair = reports['iphone-full'], reports['iphone-repair']
    compiled = build['sourceCommit']
    assert full['source_commit'] == compiled and full['scope'] == 'full'
    assert repair['scope'] == 'repair-ui'
    expected = declared('HEAD')
    assert len(expected) == 173 and declared(compiled) == expected
    assert declared(repair['source_commit']) == expected
    repair_methods = {method for method in expected if method[0] == REPAIR}
    assert len(repair_methods) == 4

    # The failed cohort is replaced in full. Unchanged tests retain their exact
    # source, while the new repair cohort must match the delivered test file.
    assert not git('diff', full['source_commit'], 'HEAD', '--', 'PelicanSaveEditorTests',
                   'PelicanSaveEditorUITests', ':(exclude)PelicanSaveEditorUITests/RepairEditorUITests.swift').strip()
    assert not git('diff', repair['source_commit'], 'HEAD', '--',
                   'PelicanSaveEditorUITests/RepairEditorUITests.swift').strip()
    permitted = {'PelicanSaveEditorUITests/RepairEditorUITests.swift',
                 'scripts/validate-on-macos.sh', '.github/workflows/verify-tracker-ui.yml',
                 'scripts/verify_build15_evidence.py'}
    changed = git('diff', '--name-only', compiled, 'HEAD').decode().splitlines()
    assert all(p in permitted or p.endswith('.md') or p.startswith('validation/') for p in changed), changed
    runtime_paths = ['PelicanSaveEditor', 'PelicanSaveEditor.xcodeproj', 'project.yml']
    for commit in {r['source_commit'] for r in reports.values()} | {'HEAD'}:
        assert not git('diff', compiled, commit, '--', *runtime_paths).strip(), commit

    native_logs = {}
    for name, report in reports.items():
        scope = expected if name == 'iphone-full' else repair_methods if name == 'iphone-repair' else {
            method for method in expected if method[0] in (REPAIR, 'ExpandedEditorUITests')}
        if name in ('mini', 'large'):
            assert report['source_commit'] == compiled and report['scope'] == 'repair'
        tests = report['tests']
        assert len(tests) == len({key(test) for test in tests}) == len(scope)
        assert set(map(key, tests)) == scope
        assert report['total_tests'] == report['declared_tests_in_scope'] == len(scope)
        assert not any(report[field] for field in ('missing', 'unexpected', 'duplicates'))
        assert report['outcomes'] == dict(Counter(t['result'] for t in tests))
        assert report['failures'] == [t for t in tests if t['result'] != 'passed']
        if name == 'iphone-full':
            assert report['status'] == 'failed' and report['outcomes'] == {'passed': 170, 'failed': 3}
            assert all(t['class'] == REPAIR for t in report['failures'])
        else:
            assert report['status'] == 'passed' and report['outcomes'] == {'passed': len(scope)}
        if artifact_root:
            device = 'iphone' if name.startswith('iphone-') else 'ipad-' + name
            logs = list((artifact_root / ('tests-' + report['source_commit'][:7]) / device).rglob('tests.log'))
            assert len(logs) == 1
            data = logs[0].read_bytes()
            assert hashlib.sha256(data).hexdigest() == report['test_log_sha256']
            log = data.decode('utf-8', errors='replace')
            observed = re.findall(r"Test Case '-\[([\w.]+) (test\w+)\]' (passed|failed|skipped) \(([\d.]+) seconds\)\.", log)
            assert [(c.split('.')[-1], m, r, float(s)) for c, m, r, s in observed] == [
                (t['class'], t['method'], t['result'], t['seconds']) for t in tests]
            if name != 'iphone-full':
                assert re.search(r'^\*\* TEST (?:EXECUTE )?SUCCEEDED \*\*$', log, re.M)
            native_logs[name] = logs[0]

    selected = [dict(t, evidence='build15-tests-iphone-full.json') for t in full['tests'] if t['class'] != REPAIR]
    selected += [dict(t, evidence='build15-tests-iphone-repair.json') for t in repair['tests']]
    assert len(selected) == 173 and set(map(key, selected)) == expected
    assert all(t['result'] == 'passed' for t in selected)
    if require_visual:
        names = {'build15-collection-review', 'build15-collection-supply', 'build15-equipment-review',
                 'build15-equipment-cancel', 'build15-equipment-invalid-damage'}
        for device, report in [('iphone', repair), ('mini', reports['mini']), ('large', reports['large'])]:
            images = folder / 'build15-ui' / device
            manifest = read(images / 'manifest.json')
            assert manifest['sourceCommit'] == report['source_commit'] and manifest['run'] == report['run_url']
            assert len(manifest['screenshots']) == 5 and {s['name'] for s in manifest['screenshots']} == names
            for shot in manifest['screenshots']:
                assert shot['visualReview'] == 'passed' and shot['reviewNotes']
                assert hashlib.sha256((images / shot['file']).read_bytes()).hexdigest() == shot['sha256']
                assert tuple(shot['test'].removesuffix('()').split('/')) in repair_methods

    summary = {
        'status': 'passed_by_split_coverage', 'compiled_source_commit': compiled,
        'repair_test_source_commit': repair['source_commit'], 'device': full['device'],
        'single_full_iphone_suite_passed': False,
        'full_run_status': full['status'], 'full_run_outcomes': full['outcomes'],
        'total_unique_tests': len(selected), 'counts_by_class': dict(Counter(t['class'] for t in selected)),
        'unchanged_methods_from_full_run': 169, 'methods_from_complete_repair_retest': 4,
        'superseded_cohort': REPAIR, 'superseded_failed_methods': full['failures'],
        'runtime_sources_identical_to_release_build': True,
        'other_test_sources_identical_to_full_run': True, 'repair_test_source_identical_to_retest': True,
        'evidence_runs': [{'report': 'build15-tests-' + name + '.json', 'url': r['run_url'],
                           'source_commit': r['source_commit'], 'job_id': r['job_id'], 'status': r['status'],
                           'outcomes': r['outcomes']} for name, r in reports.items()],
        'coverage_executions_including_ipads': 189,
        'raw_executions_in_evidence_runs': 193, 'raw_outcomes_in_evidence_runs': {'passed': 190, 'failed': 3},
        'visual_screenshots_reviewed': 15 if require_visual else None,
        'tests': sorted(selected, key=key),
        'limitations': ['The 173-method full run remains failed. All four RepairEditorUITests were subsequently retested together.',
                        'Synthetic simulator saves only; no signed device installation or real game round trip.'],
    }
    return summary, native_logs


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact-root', type=Path)
    parser.add_argument('--write-summary', action='store_true')
    args = parser.parse_args()
    summary, _ = verify(args.artifact_root)
    if args.write_summary:
        (ROOT / 'validation' / 'build15-tests-iphone.json').write_text(
            json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in summary.items() if k != 'tests'}, ensure_ascii=True, indent=2))
