
#!/data/data/com.termux/files/usr/bin/bash

set -e

PROJECT="$HOME/nammaspace"

echo "=================================="
echo "       NAMMASPACE INSTALLER"
echo "=================================="

mkdir -p "$PROJECT"/{backend,frontend,uploads,models}
cd "$PROJECT"

echo "[1/5] Installing Python dependencies"

pkg install python -y
python -m pip install fastapi uvicorn python-multipart numpy

echo "[2/5] Creating backend"

cat > backend/main.py <<'PY'
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from pathlib import Path
import shutil
import heapq
import math

ROOT = Path(__file__).resolve().parent.parent
UPLOADS = ROOT / "uploads"
MODELS = ROOT / "models"

UPLOADS.mkdir(exist_ok=True)
MODELS.mkdir(exist_ok=True)

app = FastAPI(title="NammaSpace Indoor Digital Twin")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"]
)

app.mount("/uploads", StaticFiles(directory=UPLOADS), name="uploads")
app.mount("/models", StaticFiles(directory=MODELS), name="models")

# Example indoor floor grid
# 0 = walkable
# 1 = obstacle

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
    {"id":4,"name":"Restroom","category":"Facility","x":0,"z":8},
    {"id":5,"name":"Work Area","category":"Office","x":5,"z":4}
]

class POI(BaseModel):
    name: str
    category: str = "General"
    x: int
    z: int

class RouteRequest(BaseModel):
    start: list[int]
    end: list[int]

def astar(start, end):
    rows, cols = len(grid), len(grid[0])

    def heuristic(a, b):
        return math.hypot(a[0]-b[0], a[1]-b[1])

    if not (0 <= start[0] < rows and 0 <= start[1] < cols):
        return None
    if not (0 <= end[0] < rows and 0 <= end[1] < cols):
        return None
    if grid[start[0]][start[1]] or grid[end[0]][end[1]]:
        return None

    queue = [(0, start)]
    came = {}
    cost = {tuple(start): 0}

    directions = [
        (-1,0),(1,0),(0,-1),(0,1),
        (-1,-1),(-1,1),(1,-1),(1,1)
    ]

    while queue:
        _, current = heapq.heappop(queue)

        if current == tuple(end):
            path = [current]
            while current in came:
                current = came[current]
                path.append(current)
            return path[::-1]

        for dx, dz in directions:
            nxt = (current[0]+dx,current[1]+dz)

            x,z = nxt

            if not (0 <= x < rows and 0 <= z < cols):
                continue

            if grid[x][z]:
                continue

            # Prevent diagonal corner cutting
            if dx and dz:
                if grid[current[0]+dx][current[1]]:
                    continue
                if grid[current[0]][current[1]+dz]:
                    continue

            new_cost = cost[current] + math.hypot(dx,dz)

            if nxt not in cost or new_cost < cost[nxt]:
                cost[nxt] = new_cost
                came[nxt] = current
                priority = new_cost + heuristic(nxt,end)
                heapq.heappush(queue,(priority,nxt))

    return None

@app.get("/api")
def home():
    return {
        "project":"NammaSpace",
        "status":"running",
        "version":"1.0"
    }

@app.get("/api/grid")
def get_grid():
    return {"grid":grid}

@app.get("/api/pois")
def get_pois():
    return {"pois":pois}

@app.post("/api/pois")
def add_poi(poi: POI):
    item = poi.model_dump()
    item["id"] = max([p["id"] for p in pois],default=0)+1
    pois.append(item)
    return item

@app.get("/api/search")
def search(q: str = ""):
    return {
        "results":[p for p in pois
                   if q.lower() in p["name"].lower()
                   or q.lower() in p["category"].lower()]
    }

@app.post("/api/route")
def route(request: RouteRequest):
    path = astar(
        tuple(request.start),
        tuple(request.end)
    )

    if path is None:
        return {"success":False,"message":"No walkable route found"}

    return {
        "success":True,
        "path":path,
        "distance":round(sum(
            math.hypot(
                path[i][0]-path[i-1][0],
                path[i][1]-path[i-1][1]
            ) for i in range(1,len(path))
        ),2)
    }

@app.post("/api/upload")
async def upload(file: UploadFile = File(...)):
    allowed = {".jpg",".jpeg",".png",".mp4",".webm",".glb",".gltf"}
    suffix = Path(file.filename).suffix.lower()

    if suffix not in allowed:
        return {"success":False,"message":"Unsupported file type"}

    folder = MODELS if suffix in {".glb",".gltf"} else UPLOADS
    destination = folder / Path(file.filename).name

    with destination.open("wb") as f:
        shutil.copyfileobj(file.file,f)

    return {
        "success":True,
        "filename":destination.name,
        "url":f"/{folder.name}/{destination.name}"
    }
PY

echo "[3/5] Creating frontend"

cat > frontend/index.html <<'HTML'
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>NammaSpace</title>
<style>
*{box-sizing:border-box}
body{margin:0;background:#0b1120;color:#e5edf9;font-family:Arial}
header{padding:16px;background:#111c30;border-bottom:1px solid #273750}
h1{margin:0;color:#55d6be}
main{padding:14px;max-width:1100px;margin:auto}
.panel{background:#152238;border:1px solid #2b3c55;border-radius:12px;padding:14px;margin-bottom:14px}
input,button{padding:11px;border-radius:7px;border:1px solid #40516a;margin:4px;background:#101b2c;color:white}
button{background:#167d78;cursor:pointer}
#viewer{height:430px;width:100%;border-radius:10px;overflow:hidden;background:#26344b}
#results button{display:block;width:100%;text-align:left}
small{color:#9fb2c9}
#status{color:#55d6be}
</style>
</head>
<body>
<header>
<h1>🏢 NammaSpace</h1>
<small>Intelligent Indoor Digital Twin</small>
</header>
<main>
<div class="panel">
<h3>3D Environment</h3>
<div id="viewer"></div>
<p><small>Desktop: WASD + mouse. Mobile: drag to look and use the movement controls.</small></p>
<div>
<button onclick="move(0,-1)">↑</button>
<button onclick="move(-1,0)">←</button>
<button onclick="move(0,1)">↓</button>
<button onclick="move(1,0)">→</button>
</div>
</div>

<div class="panel">
<h3>🔎 Search Indoor Locations</h3>
<input id="search" placeholder="Meeting Room A">
<button onclick="searchPOI()">Search</button>
<div id="results"></div>
</div>

<div class="panel">
<h3>🧭 Indoor Navigation</h3>
<p id="destination">Select a destination.</p>
<p id="status">Ready</p>
<button onclick="navigate()">Calculate Walking Route</button>
</div>

<div class="panel">
<h3>📍 Add Point of Interest</h3>
<input id="poiName" placeholder="Location name">
<input id="poiCategory" placeholder="Category">
<input id="poiX" type="number" placeholder="X (0-9)" min="0" max="9">
<input id="poiZ" type="number" placeholder="Z (0-9)" min="0" max="9">
<button onclick="addPOI()">Add POI</button>
</div>

<div class="panel">
<h3>📷 Upload Environment Capture</h3>
<input type="file" id="uploadFile" accept="image/*,video/*,.glb,.gltf">
<button onclick="uploadFile()">Upload</button>
<p id="uploadStatus"></p>
</div>

<div class="panel">
<h3>📦 3D Model</h3>
<input type="file" id="modelFile" accept=".glb,.gltf">
<button onclick="loadModel()">Load 3D Model</button>
<p><small>GLB files are recommended. Uploaded models can be viewed separately from the demo navigation grid.</small></p>
</div>
</main>

<script type="importmap">
{
 "imports":{
 "three":"https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.js",
 "three/addons/":"https://cdn.jsdelivr.net/npm/three@0.170.0/examples/jsm/"
 }
}
</script>
<script type="module">
import * as THREE from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';

const viewer=document.getElementById('viewer');
const scene=new THREE.Scene();
scene.background=new THREE.Color(0x18263b);

const camera=new THREE.PerspectiveCamera(70,1,0.1,1000);
camera.position.set(0,1.7,0);

const renderer=new THREE.WebGLRenderer({antialias:true});
renderer.setPixelRatio(Math.min(devicePixelRatio,2));
viewer.appendChild(renderer.domElement);

function resize(){
 const w=viewer.clientWidth,h=viewer.clientHeight;
 camera.aspect=w/h;
 camera.updateProjectionMatrix();
 renderer.setSize(w,h);
}
new ResizeObserver(resize).observe(viewer);
resize();

scene.add(new THREE.HemisphereLight(0xffffff,0x667788,2));

const light=new THREE.DirectionalLight(0xffffff,2);
light.position.set(5,10,5);
scene.add(light);

const floor=new THREE.Mesh(
 new THREE.PlaneGeometry(10,10),
 new THREE.MeshStandardMaterial({color:0x64758a})
);
floor.rotation.x=-Math.PI/2;
floor.position.set(4.5,0,4.5);
scene.add(floor);

const gridHelper=new THREE.GridHelper(10,10,0x9eb2cc,0x71849c);
gridHelper.position.set(4.5,0.02,4.5);
scene.add(gridHelper);

let selected=null;
let route=[];
let x=0,z=0;
let yaw=0,pitch=0;
const keys={};
let dragging=false,lastX=0,lastY=0;

const obstacles=[
[2,1],[3,1],[5,2],[6,2],
[1,3],[2,3],[4,4],[5,4],
[7,5],[1,6],[2,6],[5,7]
];

for(const [ox,oz] of obstacles){
 const mesh=new THREE.Mesh(
 new THREE.BoxGeometry(0.9,1,0.9),
 new THREE.MeshStandardMaterial({color:0xc06b55})
 );
 mesh.position.set(ox,0.5,oz);
 scene.add(mesh);
}

let poiMeshes=[];

function createMarker(p){
 const marker=new THREE.Mesh(
 new THREE.SphereGeometry(0.19,16,12),
 new THREE.MeshStandardMaterial({color:0x55e4bf})
 );
 marker.position.set(p.z,0.35,p.x);
 marker.userData.poi=p;
 scene.add(marker);
 poiMeshes.push(marker);
}

let pois=[];

async function refreshPOI(){
 const response=await fetch('/api/pois');
 pois=(await response.json()).pois;
 poiMeshes.forEach(m=>scene.remove(m));
 poiMeshes=[];
 pois.forEach(createMarker);
}

const raycaster=new THREE.Raycaster();
const pointer=new THREE.Vector2();

renderer.domElement.addEventListener('click',e=>{
 const rect=renderer.domElement.getBoundingClientRect();
 pointer.x=((e.clientX-rect.left)/rect.width)*2-1;
 pointer.y=-((e.clientY-rect.top)/rect.height)*2+1;
 raycaster.setFromCamera(pointer,camera);
 const hits=raycaster.intersectObjects(poiMeshes);
 if(hits.length)selectPOI(hits[0].object.userData.poi);
});

renderer.domElement.addEventListener('pointerdown',e=>{
 dragging=true;
 lastX=e.clientX;
 lastY=e.clientY;
 renderer.domElement.setPointerCapture(e.pointerId);
});
renderer.domElement.addEventListener('pointerup',()=>dragging=false);
renderer.domElement.addEventListener('pointermove',e=>{
 if(!dragging)return;
 const dx=e.clientX-lastX,dy=e.clientY-lastY;
 lastX=e.clientX;lastY=e.clientY;
 yaw-=dx*0.005;
 pitch=Math.max(-1.2,Math.min(1.2,pitch-dy*0.005));
});

document.addEventListener('keydown',e=>keys[e.key.toLowerCase()]=true);
document.addEventListener('keyup',e=>keys[e.key.toLowerCase()]=false);

function render(){
 requestAnimationFrame(render);
 const speed=0.07;
 if(keys.w||keys.arrowup)move(0,-speed);
 if(keys.s||keys.arrowdown)move(0,speed);
 if(keys.a||keys.arrowleft)move(-speed,0);
 if(keys.d||keys.arrowright)move(speed,0);
 camera.rotation.order='YXZ';
 camera.rotation.y=yaw;
 camera.rotation.x=pitch;
 camera.position.set(x,1.7,z);
 renderer.render(scene,camera);
}
render();

window.move=(dx,dz)=>{
 const nx=x+dx,nz=z+dz;
 const gx=Math.round(nz),gz=Math.round(nx);
 if(gx>=0&&gx<10&&gz>=0&&gz<10){
   if(!obstacles.some(o=>o[0]===gx&&o[1]===gz)){
     x=nx;z=nz;
   }
 }
};

window.searchPOI=async()=>{
 const q=document.getElementById('search').value;
 const data=await (await fetch('/api/search?q='+encodeURIComponent(q))).json();
 const box=document.getElementById('results');
 box.innerHTML='';
 data.results.forEach(p=>{
   const b=document.createElement('button');
   b.textContent=p.name+' — '+p.category;
   b.onclick=()=>selectPOI(p);
   box.appendChild(b);
 });
};

window.selectPOI=p=>{
 selected=p;
 document.getElementById('destination').textContent='Destination: '+p.name;
};

window.navigate=async()=>{
 if(!selected)return;
 const response=await fetch('/api/route',{
  method:'POST',
  headers:{'Content-Type':'application/json'},
  body:JSON.stringify({
   start:[Math.round(z),Math.round(x)],
   end:[selected.x,selected.z]
  })
 });
 const data=await response.json();
 document.getElementById('status').textContent=
 data.success?'Route calculated: '+data.distance+' units':'No route available';
 if(data.success){
  route=data.path;
  drawRoute();
 }
};

let routeLine=null;
function drawRoute(){
 if(routeLine)scene.remove(routeLine);
 const points=route.map(p=>new THREE.Vector3(p[1],0.09,p[0]));
 routeLine=new THREE.Line(
  new THREE.BufferGeometry().setFromPoints(points),
  new THREE.LineBasicMaterial({color:0x00ffff})
 );
 scene.add(routeLine);
}

window.addPOI=async()=>{
 const payload={
  name:document.getElementById('poiName').value,
  category:document.getElementById('poiCategory').value||'General',
  x:Number(document.getElementById('poiX').value),
  z:Number(document.getElementById('poiZ').value)
 };
 const r=await fetch('/api/pois',{
  method:'POST',
  headers:{'Content-Type':'application/json'},
  body:JSON.stringify(payload)
 });
 if(r.ok)refreshPOI();
};

window.uploadFile=async()=>{
 const file=document.getElementById('uploadFile').files[0];
 if(!file)return alert('Choose a file first');
 const fd=new FormData();
 fd.append('file',file);
 const r=await fetch('/api/upload',{method:'POST',body:fd});
 const d=await r.json();
 document.getElementById('uploadStatus').textContent=JSON.stringify(d);
};

window.loadModel=async()=>{
 const file=document.getElementById('modelFile').files[0];
 if(!file)return alert('Select a GLB model');
 const fd=new FormData();
 fd.append('file',file);
 const response=await fetch('/api/upload',{method:'POST',body:fd});
 const result=await response.json();
 if(!result.success)return alert(result.message);
 new GLTFLoader().load(result.url,gltf=>{
  scene.add(gltf.scene);
  document.getElementById('uploadStatus').textContent='3D model loaded';
 },undefined,e=>console.error(e));
};

refreshPOI();
</script>
</body>
</html>
HTML

echo "[4/5] Creating launcher"

cat > start.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
cd "$HOME/nammaspace"
echo "Starting NammaSpace..."
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000
SH

chmod +x start.sh

echo "[5/5] Installation complete!"

echo ""
echo "=================================="
echo "       NAMMASPACE READY"
echo "=================================="
echo "Run:"
echo "cd ~/nammaspace && ./start.sh"
echo ""
echo "Open browser:"
echo "http://127.0.0.1:8000"
echo "=================================="

