import math
X0 = 120.5
def mir(x): return 2*X0 - x

def catmull(points, closed=True, tension=1.0):
    P=[(p[0],p[1]) for p in points]; sharp=[p[2] if len(p)>2 else False for p in points]; n=len(P)
    g=lambda i:P[i%n]; sh=lambda i:sharp[i%n]
    d=f"M {P[0][0]:.2f} {P[0][1]:.2f} "
    rng=range(n if closed else n-1)
    for i in rng:
        p0,p1,p2,p3=g(i-1),g(i),g(i+1),g(i+2)
        if sh(i): c1=(p1[0]+(p2[0]-p1[0])/3,p1[1]+(p2[1]-p1[1])/3)
        else: c1=(p1[0]+(p2[0]-p0[0])/6*tension,p1[1]+(p2[1]-p0[1])/6*tension)
        if sh(i+1): c2=(p2[0]-(p2[0]-p1[0])/3,p2[1]-(p2[1]-p1[1])/3)
        else: c2=(p2[0]-(p3[0]-p1[0])/6*tension,p2[1]-(p3[1]-p1[1])/6*tension)
        d+=f"C {c1[0]:.2f} {c1[1]:.2f} {c2[0]:.2f} {c2[1]:.2f} {p2[0]:.2f} {p2[1]:.2f} "
    if closed: d+="Z"
    return d

def ellipse(cx,cy,rx,ry,rot_deg,nseg=16):
    th=math.radians(rot_deg); ct,st=math.cos(th),math.sin(th); pts=[]
    for k in range(nseg):
        a=2*math.pi*k/nseg; x=rx*math.cos(a); y=ry*math.sin(a)
        pts.append((cx+x*ct-y*st, cy+x*st+y*ct))
    return pts

S=True
# ---- OUTER (clockwise from L ear tip). Head (y<~110) symmetric about X0=120.5 ----
outer=[
 (38,3,S),(72,17,S),(120.5,7),(169,17,S),(203,3,S),  # ears + crown
 # right head side (outer): ear base -> TEMPLE PINCH -> bulge
 (203,18),(197,40),(208,68),(213,98),(213,120),
 # tail outer edge down to right foot
 (213,175),(203,225),(180,265),(150,300),(177,345,S),
 (79,345,S),                                          # R foot inner -> up bay right wall
 (80,308),(122,285),(162,248),(187,207),(194,165),(193,150),
 # right cheek INNER (bay right wall) up to right heart lobe
 (180,108),(192,70),(186,48),(170,40),(157,36),
 # wedge right edge down to cleft (slightly rounded)
 (141,45),(127,54),(120.5,57),
 # wedge left edge up to left heart lobe (mirror)
 (114,54),(100,45),(84,36),
 # left cheek INNER (bay left wall) down to belly
 (71,40),(55,48),(49,70),(61,108),
 (70,135),(113,152),(131,200),(120,245),(100,282),(75,310),(57,345,S),
 (1,345,S),                                           # L foot outer -> up belly outer
 (0,300),(2,250),(8,200),(20,158),(31,128),
 (43,117,S),(33,103,S),                               # armpit notch + cheek bottom
 # left head side (outer), mirror of right: bulge -> TEMPLE PINCH -> ear base
 (28,98),(33,68),(44,40),(38,18,S),
]
# eyes: rounded ovals, slightly taller than wide, mild tilt
left_eye = ellipse(86,72, 12.5,14, -14)
right_eye= ellipse(mir(86),72, 12.5,14, 14)
# beak diamond
beak=[(120.5,84,S),(132,99,S),(120.5,119,S),(109,99,S)]

paths=[catmull(outer), catmull(left_eye), catmull(right_eye), catmull(beak,tension=0.85)]
svg=f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 215 346" fill="#000000" fill-rule="evenodd" role="img" aria-label="Perch owl mark">
<path d="{' '.join(paths)}"/>
</svg>
'''
open("owl_geo.svg","w").write(svg); print("ok")
