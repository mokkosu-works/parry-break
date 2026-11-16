#!/usr/bin/env python3
"""5人分の編集可能な24秒プロジェクトを作る。動画生成は editor/render.py。"""
import copy
import json
import pathlib
import sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'promo/editor'))
import render

# 配色、台詞、カットは個別のJSONで微調整できる。
CAST = {
 'mitsuba': dict(label='ミツバ', bg='#FFF6D8', accent='#E9B400', ink='#302719', right=False,
  heads=['返せるの？','返った！','まとめて崩れる！','もう一回！'], caps=['この弾、返せる？','当たる瞬間に！','そこも崩れる！','一緒に遊ぼう'], poses=[2,4,5,0],
  clips=[('s4-7_sloppy_02',18),('s4-7_sloppy_02',21),('s3-3_just_01',3.5)],
  lines=[(0.1,'これ、返せるの？'),(3.3,'当たる瞬間に、タップ！'),(7.2,'わっ、返った！'),(11.3,'白いブロックを壊すと……'),(15.5,'まとめて、崩れた！'),(19.2,'パリィブレイク。一緒に遊ぼう！')]),
 'akane': dict(label='アカネ', bg='#28181C', accent='#FF6B62', ink='#FFF5EE', right=True,
  heads=['惜しい！','次こそ返す！','まだまだいくよ！','もう一勝負！'], caps=['次こそ！','もう一回！','点を伸ばせ！','挑戦しよう！'], poses=[3,1,4,5],
  clips=[('s2-7_just_01',23),('s2-7_just_01',3),('s2-7_just_01',11)],
  lines=[(0.1,'くっ、今の惜しい！'),(3.2,'次こそ返す！'),(8,'よし、いくよ！'),(11.4,'まだまだ、点を伸ばす！'),(19.2,'パリィブレイク。もう一勝負！')]),
 'shizuku': dict(label='シズク', bg='#121F35', accent='#7CCCE5', ink='#F1F7FC', right=False,
  heads=['音、聞いて。','タイミングを見て。','きれいに揃う。','次は、あなたの番。'], caps=['耳をすませて','当たる瞬間に。','この音、好き。','合わせてみて。'], poses=[0,1,4,5],
  clips=[('s3-3_just_01',3.5),('s3-3_just_01',6.5),('s4-7_sloppy_02',21)],
  lines=[(0.1,'この音、聞いて。'),(3.3,'当たる瞬間に、合わせて。'),(11.3,'音が揃うと、気持ちいい。'),(19.1,'パリィブレイク。次は、あなたの番。')]),
 'momoka': dict(label='モモカ', bg='#FFF0F5', accent='#D74F86', ink='#442537', right=True,
  heads=['今の、見てた？','ここからが好き！','決まった！','あなたも見せてね'], caps=['見て、見て！','少し前から','いいところ発見！','見せたくなるね'], poses=[0,1,4,5],
  clips=[('s3-3_just_01',5),('s3-3_just_01',2),('s4-7_sloppy_02',21)],
  lines=[(0.1,'今の、見てた？'),(3.3,'少し前から、もう一回！'),(7,'ここが、好きなの。'),(11.3,'これ、見せたくなるよね。'),(19.2,'パリィブレイク。あなたも遊んでみて！')]),
 'wakana': dict(label='ワカナ', bg='#EFF5E8', accent='#4F7652', ink='#263C2C', right=False,
  heads=['一面ずつ進もう','まずはこの一面','クリアできたね','自分のペースで'], caps=['ステージを選ぼう','その調子。','よかったね。','ゆっくりで大丈夫'], poses=[0,1,4,0],
  clips=[('s3-3_just_01',0),('s3-3_just_01',3.5),('s3-3_just_01',21)],
  lines=[(0.1,'今日は、一面ずつ。'),(3.3,'まずは、目の前の一面から。'),(11.3,'うん、クリアできたね。'),(16,'次も、あなたのペースで。'),(20,'パリィブレイク。ストアで検索。')]),
}

def polish(p, name):
 for sc in p['scenes']:
  layers=sc['layers'];head=next(l for l in layers if l['id']=='headline')
  head.update(fontSize=80 if name!='shizuku' else 68,strokeWidth=2,strokeColor=head['color'])
  head['x']=0;box=render._box(head);head['x']=round((1080-(box[2]-box[0]))/2)
  frame=next((l for l in layers if l['id']=='frame'),None)
  if frame:
   frame.update(y=326,height=536)
   game=next(l for l in layers if l['id']=='game');game['y']=330+(528-game['height'])//2
   mode=next(l for l in layers if l['id']=='mode');mode['y']=870
   caption=next(l for l in layers if l['id']=='caption')
   caption.update(x=caption['x']+18,y=941,fontSize=44,strokeWidth=1,strokeColor=caption['color'])
   bubble=dict(id='speech-panel',type='rect',name='字幕の背景',visible=True,x=caption['x']-18,y=925,width=445,height=110,color=frame['color'],strokeWidth=3,radius=30 if name in ['momoka','wakana'] else 8,fill='#FFFFFF' if name in ['mitsuba','momoka','wakana'] else sc['background']['color'])
   layers.insert(layers.index(caption),bubble)
   if name=='shizuku':bubble.pop('fill');bubble['strokeWidth']=1
   if name=='momoka':
    heart=dict(head,id='heart',name='ハート',text='♥',fontSize=56,x=925,y=265,color=frame['color'],strokeColor=frame['color'],strokeWidth=0)
    layers.append(heart)


def main():
 base=json.loads((render.PROJECTS/'character-promo-b.json').read_text())
 brands={l['id']:l for l in base['scenes'][1]['layers']}
 for name,c in CAST.items():
  p={'version':1,'name':f'character-{name}-v01','canvas':{'width':1080,'height':1920},'scenes':[], 'voice':{'profile':name,'lines':[{'start':t,'text':line} for t,line in c['lines']]}}
  def text(id,value,x,y,size,color=None):
   return dict(id=id,type='text',name=id,visible=True,x=x,y=y,text=value,font='../../build/fonts/DotGothic16-Regular.ttf',fontSize=size,color=color or c['ink'],strokeWidth=0,strokeColor=c['bg'],align='left')
  def rect(id,x,y,w,h,sw=3):
   return dict(id=id,type='rect',name=id,visible=True,x=x,y=y,width=w,height=h,strokeWidth=sw,color=c['accent'])
  for i,(sid,label,duration) in enumerate(render.SCENES):
   clip,offset=c['clips'][min(i,2)];src=f'../../capture/raw/{clip}.mp4'
   sc={'id':sid,'start':sum(s[2] for s in render.SCENES[:i]),'duration':duration,'background':{'src':src,'time':offset,'color':c['bg']},'layers':[]}
   layers=sc['layers']
   layers.extend([rect('top-line',100,145,880,3),rect('bottom-line',100,1490,880,2)])
   # 端の装飾も独立した編集レイヤー。
   for j in range(3):
    layers.append(rect(f'edge-{j}',30+j*18,1550+j*30,6,180-j*35,3))
   h=text('headline',c['heads'][i],0,185,72 if name!='shizuku' else 62)
   w=render._box(h)[2];h['x']=round((1080-w)/2);layers.append(h)
   if i<3:
    layers.append(rect('frame',96,326,888,508,4))
    # プレイ範囲は従来動画と同じ。選択・結果UIは全幅を収める。
    ui=name=='wakana' and i in (0,2)
    crop={'x':0 if ui else 245,'y':0,'width':2400 if ui else 1800,'height':1080}
    vh=round(880*1080/crop['width'])
    layers.append(dict(id='game',type='video',name='ゲーム映像',visible=True,x=100,y=330+(500-vh)//2,width=880,height=vh,src=src,start=offset,crop=crop))
    layers.append(text('mode','ステージ',115,845,28,c['accent']))
   else:
    layers.append(text('closing',c['caps'][i],180,440,58))
   height=480 if name=='shizuku' else 550
   x=660 if c['right'] else 110
   layers.append(dict(id='character',type='character',name=c['label'],visible=True,x=x,y=880 if i<3 else 680,height=height,src=f'../../characters/{name}_sheet.png',pose=c['poses'][i],bob=i<3 and name!='shizuku',bobAmplitude=2 if name=='wakana' else 4))
   tx=115 if c['right'] else 445
   if i<3: layers.append(text('caption',c['caps'][i],tx,935,48 if len(c['caps'][i])<9 else 42))
   # 既存のタイトルのフォント・配色・縁取りをそのまま採用。
   l=copy.deepcopy(brands['logo']);l.update(x=tx,y=1070 if i<3 else 810,width=300,height=150);layers.append(l)
   search=text('store-search','ストアで検索',tx,1230 if i<3 else 1040,36);layers.append(search)
   for k,dx in [('badge-appstore',0),('badge-googleplay',225)]:
    l=copy.deepcopy(brands[k]);l.update(x=tx+dx,y=1290 if i<3 else 1110,width=210,height=77 if k=='badge-appstore' else 81);layers.append(l)
   if i==3:
    l=copy.deepcopy(brands['app-icon']);l.update(x=470,y=600,width=125,height=125);layers.append(l)
    layers.append(text('credit','AivisSpeech:'+render.VOICE_PROFILES[name]['speakerName'],180,1370,30))
   p['scenes'].append(sc)
  polish(p, name)
  render.check(p)
  dest=render.PROJECTS/(p['name']+'.json')
  if dest.exists():raise SystemExit(f'既存プロジェクトを保護しました: {dest}')
  dest.write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n')
  print(dest.relative_to(ROOT))
if __name__=='__main__':main()
