import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('report',Path(__file__).parents[1]/'harness/stress-report.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)

class ReportTests(unittest.TestCase):
    def fixture(self):
        markers=[]
        for i,name in enumerate(r.EXPECTED['aga8']):
            start=10+i*40
            if i: markers.append({'label':'stress Chainspell applied','epoch':start-1})
            for label,epoch in [('stress phase start',start),('stress phase end',start+30)]:
                markers.append(dict(label=label,epoch=epoch,phase=name,zone=106,expected_entities=8,
                                    fixture_mode='aga',world_distance=20,entity_distance=20,x=0,y=0,z=0))
            if i:
                for cast in range(10):
                    markers.append(dict(label='stress cast completed',epoch=start+cast*2+1,
                                        spell_id=174,hit_count=8,packet_targets=8,cast_index=(i-1)*10+cast+1,damage=80))
        markers.extend([dict(label='fixture confirmed',epoch=125,expected_entities=0),dict(label='done',epoch=126)])
        markers.sort(key=lambda m:m['epoch'])
        frames=[dict(epoch=i/20,frame_ms=50,zone=106) for i in range(1,2601)]
        return frames,markers

    def test_complete(self):
        f,m=self.fixture();phases,errors=r.phases(f,m,'aga8')
        self.assertEqual(errors,[])
        self.assertTrue(all(p['valid'] for p in phases))
        self.assertEqual(phases[1]['casts'],10)
        self.assertEqual(phases[0]['fps'],20)

    def test_missing_targets(self):
        f,m=self.fixture()
        next(x for x in m if x['label']=='stress cast completed')['hit_count']=7
        phases,_=r.phases(f,m,'aga8');self.assertFalse(phases[1]['valid'])

    def test_missing_chainspell(self):
        f,m=self.fixture();m=[x for x in m if x['label']!='stress Chainspell applied']
        phases,_=r.phases(f,m,'aga8');self.assertFalse(phases[1]['valid'])

    def test_frame_gap(self):
        f,m=self.fixture();f=[x for x in f if not 20<x['epoch']<21]
        phases,_=r.phases(f,m,'aga8');self.assertFalse(phases[0]['valid'])

    def test_cleanup_and_duplicates(self):
        f,m=self.fixture();m=[x for x in m if x['label']!='fixture confirmed']
        _,errors=r.phases(f,m,'aga8');self.assertIn('final fixture cleanup unconfirmed',errors)
        m.append(next(x for x in m if x['label']=='stress phase start'))
        _,errors=r.phases(f,m,'aga8');self.assertIn('missing, reordered, or duplicate phases',errors)

    def test_no_phases(self):
        _,errors=r.phases([],[],'aga8');self.assertTrue(errors)

    def test_long_boundary_frame_preserved(self):
        f=[dict(epoch=10.5,frame_ms=1000,zone=106)]
        summary=r.effects.frame_summary(f,10,10.4,106)
        self.assertTrue(summary['valid']);self.assertEqual(summary['frames_over_500ms'],1)

if __name__=='__main__': unittest.main()
