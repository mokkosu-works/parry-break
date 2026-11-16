#!/usr/bin/env python3
"""5人のプロジェクトを事前検証して書き出し、確認結果を保存する。"""
import argparse
import json
import pathlib
import sys
ROOT=pathlib.Path(__file__).resolve().parents[3]  # promo/build/old/ から
sys.path.insert(0,str(ROOT/'promo/editor'))
import render
NAMES=['mitsuba','akane','shizuku','momoka','wakana']

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--version',choices=['v01','v02'],default='v01')
 version=parser.parse_args().version
 projects=[json.loads((render.PROJECTS/'old'/f'character-{n}-{version}.json').read_text()) for n in NAMES]  # 旧版は projects/old/
 for p in projects:
  render.check(p)
  timing,problems=render.voice_timing(render.voice_lines(p),24,profile=render.voice_profile(p))
  print(p['name'],[(l['start'],round(l['end'],2),l['text']) for l in timing],flush=True)
  if problems:raise SystemExit('\n'.join(problems))
 results=[]
 for p in projects:
  print('EXPORT '+p['name'],flush=True)
  result=render.export(p,lambda message,fraction=None:print(message,flush=True))
  results.append(result)
  (ROOT/('promo/build/out/character-series-'+version+'-validation.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
  if not all(c['ok'] for c in result['checks']):raise SystemExit(str(result))
  print(result['path'],flush=True)
if __name__=='__main__':main()
