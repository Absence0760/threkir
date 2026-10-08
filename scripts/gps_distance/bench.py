import math, random, sys
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from reference import GpsDistanceEstimator as Estimator
def course(T,v,stops=()):
    # returns true positions (m) and true speeds; loops with turns; stops = list of (start,len)
    x=y=0.0; h=0.0; pts=[]; sp=[]; true=0.0
    for t in range(T):
        stopped=any(a<=t<a+l for a,l in stops)
        s=0 if stopped else v
        if t%90==0: h+=math.radians(90 if (t//90)%3 else -60)
        x+=s*math.sin(h); y+=s*math.cos(h); true+= s if t else 0
        pts.append((x,y,math.degrees(h)%360)); sp.append(s)
    return pts,sp,true
def run(sigma,rho,white,doppler=True,stops=(),seed=1,T=1850,v=2.68):
    r=random.Random(seed); pts,sp,true=course(T,v,stops)
    nx=ny=0; k=math.sqrt(1-rho*rho); e=Estimator()
    lat0=40.0; mlat=111195.0; mlng=mlat*math.cos(math.radians(lat0))
    a=None; naive=0
    for t,((x,y,h),s) in enumerate(zip(pts,sp)):
        nx=rho*nx+k*r.gauss(0,sigma); ny=rho*ny+k*r.gauss(0,sigma)
        X=x+nx+r.gauss(0,white); Y=y+ny+r.gauss(0,white)
        lat=lat0+Y/mlat; lng=-75+X/mlng
        dsp=abs(s+r.gauss(0,0.2)) if doppler else None
        e.add_fix(float(t),lat,lng,sigma*1.2,dsp,0.4 if doppler else None,(h+r.gauss(0,10))%360 if doppler and s>0 else None)
        if a is None: a=(X,Y)
        else:
            d=math.hypot(X-a[0],Y-a[1])
            if 3<d<100: naive+=d; a=(X,Y)
    return true,naive,e.distance_m
for dop in (True,False):
  for sig,rho,w in [(3,0.9,1),(4,0.95,1.5),(3,0,0)]:
    for stops in ((),((300,120),(1200,90))):
        t,n,f=run(sig,rho,w,dop,stops)
        print(f"dop={dop} s={sig} rho={rho} stops={len(stops)}: naive {100*(n/t-1):+.1f}%  filter {100*(f/t-1):+.1f}%")
