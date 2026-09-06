#!/usr/bin/env python3
"""Validate local crowd/arrival/Chainspell workloads and summarize whole frame durations."""
import argparse
import csv
import importlib.util
import json
import math
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('effects', Path(__file__).with_name('effects-report.py'))
effects = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(effects)
EXPECTED = {
    'crowd': ['empty', 'identical-16', 'identical-32', 'mixed-32'],
    'arrivals': [x for n in range(1, 4) for x in (f'arrival-{n}', f'arrival-warm-{n}')],
    'camera': ['facing-crowd'] + [x for n, h in enumerate((0,64,128,192), 1)
                                for x in (f'turn-{n}', f'heading-{h}')],
    **{f'aga{n}': ['aga-idle','aga-round-1','aga-round-2'] for n in (8,24,40)},
}


def phases(frames, markers, scenario, distance=20):
    problems, result = [], []
    if scenario not in EXPECTED:
        return [], ['unknown stress scenario']
    expected_zone = 106 if scenario.startswith('aga') else 234
    starts = [m for m in markers if m['label'] == 'stress phase start']
    ends = [m for m in markers if m['label'] == 'stress phase end']
    if [m.get('phase') for m in starts] != EXPECTED[scenario] or [m.get('phase') for m in ends] != EXPECTED[scenario]:
        problems.append('missing, reordered, or duplicate phases')
    if not any(m['label']=='done' for m in markers) or any(m['label']=='scenario failed' for m in markers):
        problems.append('scenario did not finish successfully')
    if not any(m['label']=='fixture confirmed' and m.get('expected_entities')==0
               for m in (markers[markers.index(ends[-1])+1:] if ends else [])):
        problems.append('final fixture cleanup unconfirmed')
    last_chain = -math.inf
    for start, end in zip(starts, ends):
        errors = []
        first,last = start['epoch'],end['epoch']
        name = start.get('phase')
        if end.get('phase')!=name or last<=first:
            problems.append('invalid phase boundaries'); continue
        if any(m.get('zone')!=expected_zone for m in (start,end)):
            errors.append('wrong zone')
        if any(abs(m.get(k,-1)-distance)>0.001 for m in (start,end)
               for k in ('world_distance','entity_distance')):
            errors.append('draw distance mismatch')
        if not name.startswith('arrival-') and any(start.get(k)!=end.get(k)
                                                  for k in ('expected_entities','fixture_mode')):
            errors.append('fixture changed inside settled phase')
        summary=effects.frame_summary(frames,first,last,expected_zone)
        if not summary.get('valid'): errors.append('missing or discontinuous frame data')
        if not name.startswith(('turn-','arrival-','aga-round-')) and last-first<29:
            # Warm arrival and discrete heading holds intentionally last 20 seconds.
            if not name.startswith(('heading-','arrival-warm-')): errors.append('settled phase too short')
        target_count = (int(scenario[3:]) if scenario.startswith('aga') else
                        0 if name=='empty' else
                        int(name.rsplit('-',1)[1]) if name.startswith('identical-') else
                        32)
        if end.get('expected_entities') != target_count:
            errors.append('phase population differs from scenario definition')
        if any(abs(start.get(k, math.inf)-end.get(k, -math.inf))>0.1 for k in ('x','y','z')):
            errors.append('position missing or changed inside phase')
        casts=[m for m in markers if first<=m['epoch']<=last and m['label']=='stress cast completed']
        if name.startswith('aga-round-'):
            count=int(scenario[3:])
            chain=[m for m in markers if m['label']=='stress Chainspell applied'
                   and last_chain<m['epoch']<=first and first-m['epoch']<10]
            if len(chain)!=1: errors.append('Chainspell application unconfirmed')
            else:
                last_chain=chain[0]['epoch']
                if any(m['epoch']-last_chain>=60 for m in casts):
                    errors.append('cast outside the 60-second Chainspell window')
            first_cast = 1 if name=='aga-round-1' else 11
            if [m.get('cast_index') for m in casts] != list(range(first_cast,first_cast+10)):
                errors.append('cast sequence missing or duplicated')
            if len(casts)!=10 or any(m.get('spell_id')!=174 or m.get('packet_targets')!=min(count,15) or m.get('hit_count')!=count
                                    or m.get('damage',0)<=0 for m in casts):
                errors.append('expected ten Firaga completions with damage to every mob')
        result.append({'name':name,'start':first,'end':last,**summary,
                       'expected_entities':end.get('expected_entities'),
                       'casts':len(casts),'problems':errors,'valid':not errors})
    return result,problems


def report(output):
    base=effects.renderer.report(output)
    session=Path(json.loads((output/'active.json').read_text())['session'])
    markers=[json.loads(l) for l in (session/'perfscene-markers.jsonl').read_text().splitlines()]
    scenario=next((m['label'].split(': ',1)[1] for m in markers if m['label'].startswith('scenario start: ')), '')
    with (session/'frame-times.csv').open() as f:
        frames=[{k:float(v) for k,v in row.items()} for row in csv.DictReader(f)]
    if any(not math.isfinite(v) for r in frames for v in r.values()) or any(r['frame_ms']<=0 for r in frames):
        raise ValueError('invalid frame durations')
    values,problems=phases(frames,markers,scenario,base.get('draw_distance_requested') or 20)
    logs=[p.read_text(errors='replace') for p in session.glob('horizon-loader-*.log')]
    gpu_errors=sum('ERROR' in line and ('GPU' in line or 'command buffer' in line.lower())
                   for log in logs for line in log.splitlines())
    if gpu_errors: problems.append('GPU errors in renderer log')
    problems+=base['problems']
    timings=effects.timing_rows([line for log in logs for line in log.splitlines()])
    for p in values:
        selected=[r for r in timings if p['start']<=r['epoch']<p['end']]
        p['renderer_timings']={k:effects.durations([r[k] for r in selected if k in r])
                               for k in ('flush_ms','read_ms','wait_ms','gpu_ms')}
    return {'scenario':scenario,'valid':not problems and bool(values) and all(p['valid'] for p in values),
            'problems':problems,'phases':values,'renderer':base,
            'visual_review_required':True,
            'note':'Entity counts verify client-resident fixtures, not pixel visibility. Review screenshots. '
                   'Whole boundary frames are included. Compiler totals are not frame durations.'}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run',type=Path)
    args=parser.parse_args()
    result=report(args.run)
    print(json.dumps(result,indent=2))
    raise SystemExit(0 if result['valid'] else 1)
