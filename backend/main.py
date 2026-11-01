import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs
import heapq
import math

ROOT = Path(__file__).resolve().parent.parent

grid = [
[0,0,0,0,0,0,0,0,0,0],
[0,0,1,1,0,0,0,0,0,0],
[0,0,0,0,0,1,1,0,0,0],
[0,1,1,0,0,0,0,0,1,0],
[0,0,0,0,1,1,0,0,0,0],
[0,0,0,0,0,0,0,1,0,0],
[0,1,1,0,0,0,0,0,0,0],
[0,0,0,0,0,1,0,0,0,0],
[0,0,0,0,0,0,0,0,0,0],
[0,0,0,0,0,0,0,0,0,0]
]

pois = [
{"id":1,"name":"Reception","category":"Office","x":0,"z":0},
{"id":2,"name":"Meeting Room A","category":"Meeting","x":8,"z":0},
{"id":3,"name":"Conference Hall","category":"Hall","x":8,"z":8},
{"id":4,"name":"Restroom","category":"Facility","x":0,"z":8}
]

def astar(start,end):
    def h(a,b):
        return math.hypot(a[0]-b[0],a[1]-b[1])

    if any(not isinstance(v,int) for v in start+end):
        return None

    if not all(0<=v<10 for v in start+end):
        return None

    if grid[start[0]][start[1]] or grid[end[0]][end[1]]:
        return None

    queue=[(0,tuple(start))]
    cost={tuple(start):0}
    came={}

    directions=[
        (-1,0),(1,0),(0,-1),(0,1),
        (-1,-1),(-1,1),(1,-1),(1,1)
    ]

    while queue:
        _,cur=heapq.heappop(queue)

        if cur==tuple(end):
            path=[cur]
            while cur in came:
                cur=came[cur]
                path.append(cur)
            return path[::-1]

        for dx,dz in directions:
            nxt=(cur[0]+dx,cur[1]+dz)
            x,z=nxt

            if not(0<=x<10 and 0<=z<10):
                continue
            if grid[x][z]:
                continue

            if dx and dz:
                if grid[cur[0]+dx][cur[1]]:
                    continue
                if grid[cur[0]][cur[1]+dz]:
                    continue

            new=cost[cur]+math.hypot(dx,dz)

            if nxt not in cost or new<cost[nxt]:
                cost[nxt]=new
                came[nxt]=cur
                heapq.heappush(queue,(new+h(nxt,end),nxt))

    return None

class Server(BaseHTTPRequestHandler):

    def send_json(self,data,code=200):
        body=json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p=urlparse(self.path)
        path=p.path

        if path=="/":
            f=ROOT/"frontend"/"index.html"
            if not f.exists():
                self.send_error(404)
                return
            body=f.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type","text/html")
            self.send_header("Content-Length",str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        elif path=="/api":
            self.send_json({"project":"NammaSpace","status":"running"})

        elif path=="/api/grid":
            self.send_json({"grid":grid})

        elif path=="/api/pois":
            self.send_json({"pois":pois})

        elif path=="/api/search":
            q=parse_qs(p.query).get("q",[""])[0].lower()
            self.send_json({"results":[
                x for x in pois
                if q in x["name"].lower()
                or q in x["category"].lower()
            ]})

        else:
            self.send_error(404)

    def do_POST(self):
        global pois
        path=urlparse(self.path).path
        length=int(self.headers.get("Content-Length",0))

        if length>1000000:
            self.send_error(413)
            return

        try:
            data=json.loads(self.rfile.read(length))
        except Exception:
            self.send_error(400)
            return

        if path=="/api/route":
            route=astar(data.get("start",[]),data.get("end",[]))
            self.send_json({
                "success":route is not None,
                "path":route or [],
                "distance":round(sum(
                    math.hypot(
                        route[i][0]-route[i-1][0],
                        route[i][1]-route[i-1][1]
                    ) for i in range(1,len(route))
                ),2) if route else 0
            })

        elif path=="/api/pois":
            try:
                name=str(data["name"]).strip()
                x=data["x"]
                z=data["z"]
                if not name or len(name)>100:
                    raise ValueError()
                if type(x) is not int or type(z) is not int:
                    raise ValueError()
                if not(0<=x<10 and 0<=z<10) or grid[x][z]:
                    raise ValueError()
                if any(p["x"]==x and p["z"]==z for p in pois):
                    raise ValueError()

                item={
                    "id":max([p["id"] for p in pois],default=0)+1,
                    "name":name,
                    "category":str(data.get("category","General")),
                    "x":x,"z":z
                }
                pois.append(item)
                self.send_json(item)
            except Exception:
                self.send_json({"error":"Invalid POI data"},400)

        else:
            self.send_error(404)

    def log_message(self,fmt,*args):
        print("[NammaSpace]",fmt%args)

print("NammaSpace running at http://127.0.0.1:8000")
HTTPServer(("0.0.0.0",8000),Server).serve_forever()
from fastapi.responses import FileResponse

@app.get("/")
def frontend():
    return FileResponse(ROOT / "frontend" / "index.html")
