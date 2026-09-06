#!/usr/bin/env python3
"""Run bounded local stress scenarios with a frozen cache and reversible server fixture.

Without --execute, print the plan. An installed game/launcher must be closed first.
Each renderer-run retains its own backup and --restore recovery path.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('stress_report',HERE/'stress-report.py')
reporter=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(reporter)
GAME=Path.home()/'Games/FFXI/HorizonXI'
REMOTE='/server/scripts/commands/perfstress.lua'
SCENARIOS=tuple(reporter.EXPECTED)


def call(args, **kwargs):
    return subprocess.run(args,check=True,capture_output=True,timeout=30,**kwargs)


def host_state():
    # No process arguments or private preferences in diagnostic output.
    return {name:call(cmd,text=True).stdout for name,cmd in {
        'memory': ['vm_stat'],
        'pressure': ['sysctl','kern.memorystatus_vm_pressure_level','vm.swapusage'],
        'load': ['sysctl','vm.loadavg'],
    }.items()}


class Fixture:
    def __init__(self, root):
        self.root=root
        self.record=root/'fixture.json'

    def stage(self):
        container=call(['docker','inspect','lsb-local-map-1','--format','{{.Id}}'],text=True).stdout.strip()
        exists=subprocess.run(['docker','exec',container,'test','-e',REMOTE],timeout=30).returncode
        if exists not in (0,1): raise RuntimeError('Cannot inspect server fixture')
        if exists==0:
            raise RuntimeError('perfstress.lua already exists; restore the prior suite before continuing')
        source=HERE.parent/'lsb-docker/commands/perfstress.lua'
        record={'container':container,'path':REMOTE,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
        self.record.write_text(json.dumps(record,indent=2)+'\n')
        call(['docker','exec','-i',container,'python3','-c',
              'import sys; open(sys.argv[1], "xb").write(sys.stdin.buffer.read())',REMOTE],
             input=source.read_bytes())
        installed=call(['docker','exec',container,'cat',REMOTE]).stdout
        if hashlib.sha256(installed).hexdigest()!=record['sha256']:
            raise RuntimeError('Server fixture copy did not match')

    def restore(self):
        if not self.record.exists(): return
        record=json.loads(self.record.read_text())
        exists=subprocess.run(['docker','exec',record['container'],'test','-e',REMOTE],timeout=30).returncode
        if exists==0:
            data=call(['docker','exec',record['container'],'cat',REMOTE]).stdout
            if hashlib.sha256(data).hexdigest()!=record['sha256']:
                raise RuntimeError('Server fixture changed; refusing to remove it')
            call(['docker','exec',record['container'],'rm',REMOTE])
        elif exists!=1: raise RuntimeError('Could not verify server fixture removal')
        (self.root/'fixture-restored.json').write_text(json.dumps({'removed':True})+'\n')


def command(root, scenario, options):
    args=[sys.executable,str(HERE/'renderer-run.py'),'--output',str(root/scenario),
          '--scenario',scenario,'--menu-sample','0',
          '--limit','420','--capture-seconds','400','--level',getattr(options,'level','standard-nosample'),
          '--shader-cache',str(root/'inputs/shaders.bin'),
          '--env','PERFSCENE_FRAMES={session}\\frame-times.csv']
    if getattr(options,'renderer_bundle',None):
        args+=['--renderer-bundle',str(options.renderer_bundle.resolve()),
               '--renderer-config',options.renderer_config,'--renderer-log',options.renderer_log]
    else: args+=['--installed-mtld3d']
    if not getattr(options,'network',False): args+=['--no-network']
    if getattr(options,'dump_scene',None): args+=['--dump-scene',options.dump_scene]
    for value in getattr(options,'env',[]): args+=['--env',value]
    if not options.minimal: args+=['--boot-file',str(root/'inputs/boot.txt')]
    if options.graphics_profile: args+=['--graphics-profile',str(options.graphics_profile.resolve())]
    if options.background: args+=['--background',str(options.background)]
    return args


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path)
    p.add_argument('--restore-fixture',type=Path)
    p.add_argument('--scenario',action='append',choices=SCENARIOS)
    p.add_argument('--execute',action='store_true')
    p.add_argument('--network',action='store_true',help='include nettop; omitted by default to reduce capture overhead')
    p.add_argument('--minimal',action='store_true',help='diagnostic addon comparison; default full boot script')
    p.add_argument('--boot-file',type=Path,default=GAME/'scripts/default.txt')
    p.add_argument('--graphics-profile',type=Path)
    p.add_argument('--background',type=int,choices=(1024,2048,4096))
    p.add_argument('--renderer-bundle',type=Path,help='isolated candidate; default installed mtld3d')
    p.add_argument('--renderer-config',default='color.hdr.enable=false;render.scale=1;present.maxFps=0;render.mergePasses=true;render.submitDraws=0')
    p.add_argument('--renderer-log',default='mtld3d=info')
    p.add_argument('--level',choices=('standard-nosample','standard'),default='standard-nosample')
    p.add_argument('--dump-scene',help='bounded renderer F12 dump at a settled screenshot label')
    p.add_argument('--env',action='append',default=[],help='diagnostic override subject to renderer-run validation')
    p.add_argument('--shader-cache',type=Path,default=GAME/'bootloader/mtld3d_shaders.bin')
    a=p.parse_args()
    if a.restore_fixture:
        Fixture(a.restore_fixture.resolve()).restore(); return 0
    scenarios=a.scenario or list(SCENARIOS)
    if len(set(scenarios))!=len(scenarios): p.error('Use separate output directories for repeated scenarios')
    print(json.dumps({'scenarios':scenarios,'game_limit_seconds':420,'suite_limit_seconds':3600,
                      'addons':'minimal' if a.minimal else 'full boot script',
                      'cache':'same frozen seed for every run',
                      'graphics':'supplied numeric profile' if a.graphics_profile else 'saved local profile'},indent=2),flush=True)
    if not a.execute: return 0
    if not a.output: p.error('--execute requires --output outside Git')
    processes=call(['ps','-axo','pid=,comm='],text=True).stdout.lower()
    if any(name in processes for name in ('horizon-loader.exe','ffxi-on-mac.app/contents/macos','wineserver')):
        p.error('Close the game, launcher and Wine before running the suite')
    root=a.output.expanduser().resolve()
    existing=root
    while not existing.exists(): existing=existing.parent
    if subprocess.run(['git','-C',str(existing),'rev-parse','--show-toplevel'],capture_output=True).returncode==0:
        p.error('Output must be outside Git')
    root.mkdir(parents=True,exist_ok=False)
    inputs=root/'inputs'; inputs.mkdir(mode=0o700)
    shutil.copy2(a.shader_cache,inputs/'shaders.bin')
    if not a.minimal: shutil.copy2(a.boot_file,inputs/'boot.txt')
    (root/'inputs.json').write_text(json.dumps({f.name:hashlib.sha256(f.read_bytes()).hexdigest()
                                               for f in inputs.iterdir()},indent=2)+'\n')
    fixture=Fixture(root)
    started=time.monotonic()
    results=[]
    try:
        fixture.stage()
        for scenario in scenarios:
            if time.monotonic()-started>3060: raise RuntimeError('Suite deadline leaves no time for another bounded run')
            (root/f'{scenario}-host-before.json').write_text(json.dumps(host_state(),indent=2)+'\n')
            with (root/f'{scenario}-driver.log').open('w') as log:
                child=subprocess.Popen(command(root,scenario,a),stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
                try: code=child.wait(timeout=540)
                except (subprocess.TimeoutExpired,KeyboardInterrupt):
                    os.killpg(child.pid,signal.SIGTERM)
                    try: child.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid,signal.SIGKILL); child.wait(timeout=10)
                    raise RuntimeError(f'Run interrupted; inspect {root/scenario} and use renderer-run --restore if required')
            (root/f'{scenario}-host-after.json').write_text(json.dumps(host_state(),indent=2)+'\n')
            if code: raise RuntimeError(f'{scenario} failed; see its driver log and restoration record')
            result=reporter.report(root/scenario)
            (root/f'{scenario}-report.json').write_text(json.dumps(result,indent=2)+'\n')
            results.append(result)
            print(f'{scenario}: '+('valid' if result['valid'] else 'INVALID'),flush=True)
            if not result['valid']: raise RuntimeError('Invalid workload; suite stopped')
    finally:
        fixture.restore()
        (root/'suite-report.json').write_text(json.dumps(results,indent=2)+'\n')
    return 0

if __name__=='__main__':
    raise SystemExit(main())
