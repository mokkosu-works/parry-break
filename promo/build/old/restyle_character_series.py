#!/usr/bin/env python3
"""構成案に寄せたv02。元のv01や録画・キャラ素材は上書きしない。"""
import copy
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]  # promo/build/old/ から
sys.path.insert(0,str(ROOT/'promo/editor'))
import render
from create_character_series import CAST
FONT='../../build/fonts/NotoSansCJK-Black.ttc'
BOLD='../../build/fonts/NotoSansCJK-Bold.ttc'
CAPTIONS={
 'mitsuba':['この弾、\n返せる？','返った！','そこも\n崩れる！'],
 'akane':['次こそ！','もう一回！','まだまだ！'],
 'shizuku':['音、聞いて。','当たる\n瞬間に。','この音、好き。'],
 'momoka':['見て、見て！','ここが\n好きなの。','決まった！'],
 'wakana':['一面ずつ\n進もう','その調子。','できたね。'],
}

def shape(id,kind,x,y,w,h,color,fill=None,sw=3,tail='left'):
 result=dict(id=id,name=id,type='rect',visible=True,x=x,y=y,width=w,height=h,color=color,strokeWidth=sw,shape=kind,tail=tail)
 if fill:result['fill']=fill
 return result


def fit_text(layer,box,font=FONT,size=72,color=None):
 layer.update(font=font,fontSize=size,strokeWidth=0,align='center')
 if color:layer['color']=color
 while True:
  layer.update(x=0,y=0);a,b,c,d=render._box(layer)
  if c-a<=box[2] and d-b<=box[3]:break
  layer['fontSize']-=1
 layer['x']=round(box[0]+(box[2]-(c-a))/2-a)
 layer['y']=round(box[1]+(box[3]-(d-b))/2-b)
 return layer


def decorations(name,c):
 color=c['accent'];decor=[]
 if name in ('mitsuba','akane'):
  for i in range(3):
   decor.append(shape('top-stripe-'+str(i),'slash',-50+i*80,-20,180,190,color,color,1))
   decor.append(shape('bottom-stripe-'+str(i),'slash',870+i*80,1720,160,210,color,color,1))
  if name=='mitsuba':
   for r in range(4):
    for col in range(6):
     decor.append(shape(f'dot-{r}-{col}','dot',870+col*30,45+r*30,6,6,color,color,1))
 else:
  if name=='shizuku':
   for i,(x,y,w) in enumerate([(100,110,620),(170,130,680),(160,1760,500),(330,1785,650)]):
    decor.append(shape('line-'+str(i),'rect',x,y,w,3,color,color,1))
  elif name=='momoka':
   for i,(x,y,size) in enumerate([(-70,-70,220),(960,80,90),(940,1700,200),(-30,1830,140)]):
    decor.append(shape('heart-'+str(i),'heart',x,y,size,size,'#F3A4C4','#F3A4C4',1))
   decor.append(shape('heart-small','heart',910,1200,52,52,color,color,1))
  else:
   for i,(x,y,w,h) in enumerate([(900,-10,140,90),(965,60,110,80),(20,1770,100,170),(105,1830,120,80),(955,1780,150,100)]):
    decor.append(shape('leaf-'+str(i),'leaf',x,y,w,h,'#91B469','#91B469',1))
 return decor


def main():
 for name,c in CAST.items():
  p=json.loads((render.PROJECTS/'old'/f'character-{name}-v01.json').read_text());p['name']='character-'+name+'-v02'
  for i,sc in enumerate(p['scenes']):
   old={l['id']:copy.deepcopy(l) for l in sc['layers']}
   layers=decorations(name,c)
   head=fit_text(old['headline'],(100,160,880,135),size=100,color=c['ink']);layers.append(head)
   if name in ('akane','wakana'):
    layers.append(shape('headline-swoosh','slash',360,302,510,18,c['accent'],c['accent'],1))
   char=old['character'];char.update(isolate=True,height=680 if name!='shizuku' else 620,x=640 if c['right'] else 100,y=820 if name!='shizuku' else 865)
   if i<3:
    game=old['game'];game.update(x=100,y=350+(528-game['height'])//2)
    frame=shape('frame','rect',91,341,898,546,c['ink'],None,4)
    frame['radius']=24 if name=='momoka' else 12
    layers.extend([frame,game])
    # 上の帯の右寄せラベル。人物や弾の経路と重ねない。
    mode=old['mode'];fit_text(mode,(760,895,210,43),font=BOLD,size=30,color=c['accent']);layers.append(mode)
    bx=110 if c['right'] else 470
    kind={'mitsuba':'speech','akane':'burst','shizuku':'speech','momoka':'cloud','wakana':'oval'}[name]
    bc=c['ink'] if name in ('mitsuba','wakana') else c['accent']
    fill=c['bg'] if name in ('akane','shizuku') else '#FFFEF9'
    bubble=shape('speech-panel',kind,bx,955,490,255,bc,fill,6 if name!='shizuku' else 3,'right' if c['right'] else 'left')
    layers.append(bubble)
    caption=old['caption'];caption['text']=CAPTIONS[name][i]
    fit_text(caption,(bx+55,993,380,138),size=64 if name!='shizuku' else 53,color=c['ink']);layers.append(caption)
    if name=='mitsuba':
     for j in range(2):layers.append(shape('spark-'+str(j),'spark',890+j*40,915-j*30,20,35,c['accent'],c['accent'],1))
   else:
    fit_text(old['closing'],(130,370,820,100),size=62,color=c['ink']);layers.append(old['closing'])
    char.update(y=630,height=720 if name!='shizuku' else 660)
    icon=old['app-icon'];icon.update(x=480,y=565,width=130,height=130);layers.append(icon)
   layers.append(char)
   lx=150 if c['right'] else 500
   for key,y in [('logo-parry',1208),('logo-break',1290)]:
    logo=old[key];logo.update(x=lx,y=y if i<3 else y-380,fontSize=78);layers.append(logo)
   search=old['store-search'];fit_text(search,(lx,1393 if i<3 else 1045,390,40),font=BOLD,size=30,color=c['ink']);layers.append(search)
   if i==3:
    for key,dx in [('badge-appstore',0),('badge-googleplay',205)]:
     badge=old[key];badge.update(x=lx+dx,y=1130,width=190,height=70 if key=='badge-appstore' else 74);layers.append(badge)
    credit=old['credit'];fit_text(credit,(150,1370,780,45),font=BOLD,size=29,color=c['ink']);layers.append(credit)
   sc['layers']=layers
  render.check(p)
  dest=render.PROJECTS/'old'/(p['name']+'.json')
  if dest.exists():raise SystemExit(f'既存ファイルを保護しました: {dest}')
  dest.write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n');print(dest.name)
if __name__=='__main__':main()
