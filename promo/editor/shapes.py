"""編集可能な吹き出し・飾り。書き出しとプレビューで同じ描画を使う。"""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

SHAPES = ('rect', 'speech', 'burst', 'cloud', 'oval', 'heart', 'leaf', 'slash', 'dot', 'spark')


def pixels(layer):
    w, h = round(layer['width']), round(layer['height'])
    scale = 2
    sw = round(layer.get('strokeWidth', 3))
    mask = Image.new('L', ((w + 1) * scale, (h + 1) * scale))
    d = ImageDraw.Draw(mask)
    shape = layer.get('shape', 'rect')
    def pts(points): return [(round(x * w * scale), round(y * h * scale)) for x, y in points]
    margin = (sw + 2) * scale
    box = (margin, margin, w * scale - margin, h * scale - margin)
    if shape == 'rect':
        d.rounded_rectangle(box, radius=round(layer.get('radius', 0) * scale), fill=255)
    elif shape == 'burst':
        poly=[]
        for i in range(24):
            a = 2 * math.pi * i / 24
            radius = .46 if i % 2 == 0 else .37
            poly.append((.5 + radius * math.cos(a), .5 + radius * math.sin(a)))
        d.polygon(pts(poly), fill=255)
    elif shape in ('speech', 'cloud', 'oval'):
        if shape == 'speech':
            d.rounded_rectangle((margin, margin, w*scale-margin, h*scale*.78), radius=min(h*.22,w*.15)*scale, fill=255)
        elif shape == 'oval':
            d.ellipse((margin,margin,w*scale-margin,h*scale*.82), fill=255)
        else:
            d.rounded_rectangle((w*.08*scale,h*.14*scale,w*.92*scale,h*.72*scale), radius=h*.2*scale,fill=255)
            for cx,cy,rx,ry in [(.18,.28,.16,.23),(.37,.22,.20,.20),(.63,.21,.20,.19),(.83,.29,.15,.22),(.20,.54,.17,.22),(.47,.59,.22,.19),(.76,.55,.20,.22)]:
                d.ellipse(pts([(cx-rx,cy-ry),(cx+rx,cy+ry)]),fill=255)
        if layer.get('tail', 'left') == 'right':
            tail=[(.65,.63),(.83,.63),(.94,.96),(.70,.77)]
        else:
            tail=[(.17,.63),(.35,.63),(.30,.77),(.06,.96)]
        d.polygon(pts(tail),fill=255)
    elif shape == 'heart':
        points=[]
        for i in range(101):
            t=2*math.pi*i/100
            x=16*math.sin(t)**3
            y=13*math.cos(t)-5*math.cos(2*t)-2*math.cos(3*t)-math.cos(4*t)
            points.append((.5+x/36,.48-y/34))
        d.polygon(pts(points),fill=255)
    elif shape == 'leaf':
        # 先端から反対側へ、2本の曲線で作る細長い葉。
        points=[]
        for i in range(41):
            t=i/40
            points.append((.08+.84*t,.90-.8*t-.32*math.sin(math.pi*t)))
        for i in range(40,-1,-1):
            t=i/40
            points.append((.08+.84*t,.90-.8*t+.26*math.sin(math.pi*t)))
        d.polygon(pts(points),fill=255)
    elif shape == 'slash':
        d.polygon(pts([(.02,.98),(.67,.02),(.98,.02),(.33,.98)]),fill=255)
    elif shape == 'dot':
        d.ellipse(box,fill=255)
    elif shape == 'spark':
        d.polygon(pts([(.5,.02),(.61,.38),(.98,.5),(.61,.62),(.5,.98),(.39,.62),(.02,.5),(.39,.38)]),fill=255)
    outside=mask.filter(ImageFilter.MaxFilter(2*sw*scale+1))
    border=ImageChops.subtract(outside,mask)
    im=Image.new('RGBA', mask.size)
    fill=layer.get('fill')
    if fill:
        im.paste(Image.new('RGBA',mask.size,fill), (0,0),mask)
    im.paste(Image.new('RGBA',mask.size,layer['color']), (0,0),border)
    return im.resize((w+1,h+1),Image.Resampling.LANCZOS)
