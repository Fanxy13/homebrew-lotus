// lotus – 3D hero: a procedural lotus blooming on dark water
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

const canvas = document.getElementById('scene');
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
const small = innerWidth < 700;

let renderer;
try {
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance', preserveDrawingBuffer: location.search.includes('debug') });
} catch {
  canvas.remove();
  document.body.classList.add('no-webgl');
}

// Start after the first paint, so the page shows up instantly
if (renderer) requestAnimationFrame(() => setTimeout(init, 0));

function init() {
  renderer.setPixelRatio(Math.min(devicePixelRatio, small ? 1.5 : 1.75));
  renderer.setSize(innerWidth, innerHeight, false);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;

  const BG = new THREE.Color(0x05070a);
  const scene = new THREE.Scene();
  scene.background = BG;
  scene.fog = new THREE.FogExp2(BG, 0.045);

  const camera = new THREE.PerspectiveCamera(small ? 40 : 30, innerWidth / innerHeight, 0.1, 100);
  const camBase = new THREE.Vector3(0, 1.75, small ? 12 : 9.4);
  const look = new THREE.Vector3(0, 0.55, 0);
  camera.position.copy(camBase);
  // Shift the frame so the flower sits in the upper part, above the headline
  const reframe = () => camera.setViewOffset(innerWidth, innerHeight, 0, innerHeight * (small ? 0.24 : 0.235), innerWidth, innerHeight);
  reframe();

  // ── Theme colors come straight from the CSS variables ─────────
  const css = (name) => new THREE.Color(getComputedStyle(document.documentElement).getPropertyValue(name).trim() || '#ffffff');
  const theme = {};
  const readTheme = () => ({ logo: css('--logo'), key: css('--key'), salute: css('--salute'), key2: css('--key2') });
  Object.assign(theme, readTheme());

  // ── Lights ────────────────────────────────────────────────────
  scene.add(new THREE.HemisphereLight(0xfff4f6, 0x0b1411, 1.2));
  const sun = new THREE.DirectionalLight(0xfff1e4, 1.7);
  sun.position.set(3, 6, 5);
  scene.add(sun);
  const rim = new THREE.PointLight(theme.logo, 40, 14, 2);
  rim.position.set(-2.6, 2.4, -2.8);
  scene.add(rim);
  const core = new THREE.PointLight(theme.salute, 2.2, 3, 2);
  core.position.set(0, 0.9, 0);
  scene.add(core);

  // ── Petal geometry: curved, cupped, pointed ───────────────────
  function petalGeometry(len, wid, cup, curl) {
    const U = 26, V = 12, pos = [], uv = [], idx = [];
    for (let i = 0; i <= U; i++) {
      const u = i / U;
      const w = wid * Math.pow(Math.sin(Math.PI * Math.pow(u, 0.78)), 0.8);
      for (let j = 0; j <= V; j++) {
        const v = (j / V) * 2 - 1;
        pos.push(v * w, u * len, cup * (1 - v * v) * w + curl * u * u * len);
        uv.push(u, v);
      }
    }
    for (let i = 0; i < U; i++) {
      for (let j = 0; j < V; j++) {
        const a = i * (V + 1) + j, b = a + V + 1;
        idx.push(a, b, a + 1, b, b + 1, a + 1);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.setAttribute('color', new THREE.Float32BufferAttribute(new Float32Array(pos.length), 3));
    g.setIndex(idx);
    g.computeVertexNormals();
    return g;
  }

  // Paints a petal: creamy base → theme color towards tip and edges
  function paint(g, base, tip, heart) {
    const uv = g.attributes.uv, col = g.attributes.color, c = new THREE.Color();
    for (let k = 0; k < uv.count; k++) {
      const u = uv.getX(k), v = Math.abs(uv.getY(k));
      const t = Math.min(1, Math.pow(u, 1.5) * 1.05 + v * v * 0.35);
      c.copy(base).lerp(tip, t);
      if (u < 0.18) c.lerp(heart, (0.18 - u) / 0.18 * 0.55);
      col.setXYZ(k, c.r, c.g, c.b);
    }
    col.needsUpdate = true;
  }

  const layers = [
    { n: 9, len: 1.6, wid: 0.6, cup: 0.36, curl: 0.16, r: 0.2, open: 1.12, closed: 0.42, delay: 0.15 },
    { n: 9, len: 1.48, wid: 0.56, cup: 0.44, curl: 0.1, r: 0.16, open: 0.74, closed: 0.22, delay: 0.4, offset: 0.5 },
    { n: 7, len: 1.28, wid: 0.5, cup: 0.5, curl: 0.05, r: 0.12, open: 0.4, closed: 0.08, delay: 0.65 },
    { n: 5, len: 1.0, wid: 0.38, cup: 0.55, curl: 0.0, r: 0.07, open: 0.14, closed: 0.02, delay: 0.9, offset: 0.3 },
  ];
  for (const L of layers) L.geo = petalGeometry(L.len, L.wid, L.cup, L.curl);

  const petalMat = new THREE.MeshPhysicalMaterial({
    vertexColors: true, side: THREE.DoubleSide, roughness: 0.48,
    sheen: 1, sheenRoughness: 0.45, sheenColor: theme.logo,
    clearcoat: 0.25, clearcoatRoughness: 0.6,
    emissive: theme.logo, emissiveIntensity: 0.05,
  });

  const podMat = new THREE.MeshStandardMaterial({ color: theme.key2, emissive: theme.salute, emissiveIntensity: 0.55, roughness: 0.5 });
  const stamenMat = new THREE.MeshStandardMaterial({ color: theme.salute, emissive: theme.salute, emissiveIntensity: 2.4 });

  // Builds one flower (used twice: real + reflection)
  function buildFlower() {
    const group = new THREE.Group();
    const petals = [];
    layers.forEach((L, li) => {
      for (let k = 0; k < L.n; k++) {
        const a = ((k + (L.offset || 0)) / L.n) * Math.PI * 2 + li * 0.21;
        const pivot = new THREE.Group();
        pivot.position.set(Math.sin(a) * L.r, 0.02 + li * 0.015, Math.cos(a) * L.r);
        pivot.rotation.y = a;
        const mesh = new THREE.Mesh(L.geo, petalMat);
        const s = 0.92 + ((k * 7919) % 13) / 100;
        mesh.scale.set(s, s, s);
        pivot.add(mesh);
        group.add(pivot);
        petals.push({ mesh, L, phase: k * 1.7 + li, jitter: (((k * 31) % 7) - 3) * 0.018 });
      }
    });
    // seed pod + glowing stamens
    const pod = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.16, 0.22, 36), podMat);
    pod.position.y = 0.32;
    group.add(pod);
    const seeds = new THREE.InstancedMesh(new THREE.SphereGeometry(0.03, 10, 8), new THREE.MeshStandardMaterial({ color: 0x3a3f1c, roughness: 0.6 }), 9);
    const m = new THREE.Matrix4();
    for (let i = 0; i < 9; i++) {
      const a = (i / 8) * Math.PI * 2, r = i === 8 ? 0 : 0.13;
      m.makeTranslation(Math.sin(a) * r, 0.435, Math.cos(a) * r);
      seeds.setMatrixAt(i, m);
    }
    group.add(seeds);
    const stamens = new THREE.InstancedMesh(new THREE.SphereGeometry(0.022, 8, 6), stamenMat, 70);
    for (let i = 0; i < 70; i++) {
      const a = i * 2.39996, r = 0.27 + (i % 5) * 0.02, y = 0.24 + (i % 7) * 0.025;
      m.makeTranslation(Math.sin(a) * r, y, Math.cos(a) * r);
      stamens.setMatrixAt(i, m);
    }
    group.add(stamens);
    return { group, petals };
  }

  const flower = buildFlower();
  const mirror = buildFlower();
  mirror.group.scale.y = -1;
  scene.add(flower.group, mirror.group);

  function paintAll() {
    const base = new THREE.Color(0xfff6f0).lerp(theme.logo, 0.24);
    const heart = theme.salute.clone().lerp(new THREE.Color(0xffffff), 0.3);
    for (const L of layers) paint(L.geo, base, theme.logo, heart);
    petalMat.sheenColor.copy(theme.logo);
    petalMat.emissive.copy(theme.logo);
    podMat.color.copy(theme.key2);
    podMat.emissive.copy(theme.salute);
    stamenMat.color.copy(theme.salute);
    stamenMat.emissive.copy(theme.salute);
    rim.color.copy(theme.logo);
    core.color.copy(theme.salute);
    padMat.color.copy(theme.key).multiplyScalar(0.28);
    water.uniforms.uTint.value.copy(theme.logo);
    pollen.material.uniforms.uA.value.copy(theme.salute);
    pollen.material.uniforms.uB.value.copy(theme.logo);
  }

  // ── Water with ripples (covers the reflection) ────────────────
  const water = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false,
    uniforms: { uTime: { value: 0 }, uTint: { value: theme.logo.clone() }, uBg: { value: BG }, uCam: { value: camera.position } },
    vertexShader: `
      varying vec3 vW;
      void main() { vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }`,
    fragmentShader: `
      uniform float uTime; uniform vec3 uTint; uniform vec3 uBg; uniform vec3 uCam;
      varying vec3 vW;
      void main() {
        float d = length(vW.xz);
        float rip = 0.0;
        for (int k = 0; k < 3; k++) {
          float p = fract(uTime * 0.09 + float(k) / 3.0);
          float r = 0.9 + p * 9.0;
          rip += exp(-pow((d - r) * 4.0, 2.0)) * (1.0 - p) * 0.5;
        }
        float shimmer = 0.5 + 0.5 * sin(vW.x * 3.1 + uTime * 0.7) * sin(vW.z * 2.7 - uTime * 0.5);
        float glow = exp(-d * d * 0.35) * 0.32;
        vec3 col = uBg + uTint * (rip * 0.45 + glow + shimmer * 0.015);
        float fade = smoothstep(26.0, 6.0, distance(vW, uCam));
        gl_FragColor = vec4(col, mix(1.0, 0.9, fade));
      }`,
  });
  const waterMesh = new THREE.Mesh(new THREE.PlaneGeometry(80, 80, 1, 1), water);
  waterMesh.rotation.x = -Math.PI / 2;
  scene.add(waterMesh);

  // ── Lily pads ─────────────────────────────────────────────────
  const padMat = new THREE.MeshStandardMaterial({ color: theme.key.clone().multiplyScalar(0.28), roughness: 0.6, side: THREE.DoubleSide });
  const pads = [];
  [[2.6, 0.8, 0.75], [-2.9, -0.6, 0.95], [1.4, -2.4, 0.6], [-1.7, 2.1, 0.5], [4.2, -2.8, 1.1], [-4.6, 1.2, 0.8]].forEach(([x, z, r], i) => {
    const pad = new THREE.Mesh(new THREE.CircleGeometry(r, 48, 0.2, Math.PI * 2 - 0.4), padMat);
    pad.rotation.set(-Math.PI / 2, 0, i * 1.3);
    pad.position.set(x, 0.012, z);
    pads.push({ pad, phase: i * 1.1 });
    scene.add(pad);
  });

  // ── Pollen: soft glowing particles, animated in the shader ────
  const N = small ? 140 : 320;
  const pBase = new Float32Array(N * 3), pSeed = new Float32Array(N * 2);
  for (let i = 0; i < N; i++) {
    const a = Math.random() * Math.PI * 2, r = 0.5 + Math.pow(Math.random(), 0.6) * 6.5;
    pBase.set([Math.sin(a) * r, Math.random() * 5, Math.cos(a) * r], i * 3);
    pSeed.set([0.08 + Math.random() * 0.22, Math.random() * 6.28], i * 2);
  }
  const pGeo = new THREE.BufferGeometry();
  pGeo.setAttribute('position', new THREE.BufferAttribute(pBase, 3));
  pGeo.setAttribute('aSeed', new THREE.BufferAttribute(pSeed, 2));
  const pollen = new THREE.Points(pGeo, new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    uniforms: { uTime: { value: 0 }, uA: { value: theme.salute.clone() }, uB: { value: theme.logo.clone() }, uPx: { value: renderer.getPixelRatio() } },
    vertexShader: `
      uniform float uTime; uniform float uPx; attribute vec2 aSeed; varying float vT; varying float vMix;
      void main() {
        vec3 p = position;
        p.y = mod(p.y + uTime * aSeed.x, 5.0);
        p.x += sin(uTime * 0.4 + aSeed.y) * 0.25;
        p.z += cos(uTime * 0.3 + aSeed.y) * 0.25;
        vT = 0.5 + 0.5 * sin(uTime * 2.0 + aSeed.y * 3.0);
        vT *= smoothstep(0.0, 0.6, p.y) * smoothstep(5.0, 3.6, p.y);
        vMix = fract(aSeed.y);
        vec4 mv = modelViewMatrix * vec4(p, 1.0);
        gl_PointSize = (28.0 + 30.0 * vT) * uPx / -mv.z;
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: `
      uniform vec3 uA; uniform vec3 uB; varying float vT; varying float vMix;
      void main() {
        float d = length(gl_PointCoord - 0.5);
        float a = smoothstep(0.5, 0.0, d);
        gl_FragColor = vec4(mix(uA, uB, vMix) * (0.6 + vT), a * a * (0.25 + 0.75 * vT));
      }`,
  }));
  scene.add(pollen);

  paintAll();

  // ── Post-processing: bloom ────────────────────────────────────
  const composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), small ? 0.4 : 0.5, 0.5, 0.86);
  composer.addPass(bloom);
  composer.addPass(new OutputPass());

  // ── Interaction ───────────────────────────────────────────────
  const pointer = new THREE.Vector2();
  addEventListener('pointermove', (e) => {
    pointer.set(e.clientX / innerWidth - 0.5, e.clientY / innerHeight - 0.5);
  }, { passive: true });

  let scroll = 0;
  const onScroll = () => {
    scroll = Math.min(2.5, scrollY / innerHeight);
    canvas.style.opacity = String(Math.max(0.28, 1 - scroll * 0.6));
  };
  addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  addEventListener('resize', () => {
    camera.aspect = innerWidth / innerHeight;
    reframe();
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight, false);
    composer.setSize(innerWidth, innerHeight);
  });

  // Theme switch: blend smoothly from the old to the new colors
  let blend = null;
  addEventListener('lotus-theme', () => {
    blend = { from: { ...Object.fromEntries(Object.entries(theme).map(([k, v]) => [k, v.clone()])) }, to: readTheme(), t0: performance.now() };
  });

  // ── Loop ──────────────────────────────────────────────────────
  const ease = (x) => 1 - Math.pow(1 - x, 3);
  const t0 = performance.now();
  const tmp = new THREE.Vector3();
  let frame = 0;

  function tick() {
    const t = reduce ? 6 : (performance.now() - t0) / 1000;

    for (const f of [flower, mirror]) {
      for (const p of f.petals) {
        const k = ease(Math.min(1, Math.max(0, (t - 0.4 - p.L.delay) / 2.6)));
        p.mesh.rotation.x = p.L.closed + (p.L.open - p.L.closed) * k + p.jitter * k + Math.sin(t * 0.9 + p.phase) * 0.022 * k;
      }
    }
    const bob = Math.sin(t * 0.8) * 0.035;
    flower.group.rotation.y = mirror.group.rotation.y = t * 0.05;
    flower.group.position.y = bob;
    mirror.group.position.y = -bob;
    for (const { pad, phase } of pads) pad.position.y = 0.012 + Math.sin(t * 0.7 + phase) * 0.012;

    if (blend) {
      const k = Math.min(1, (performance.now() - blend.t0) / 900);
      for (const key in blend.to) theme[key].copy(blend.from[key]).lerp(blend.to[key], ease(k));
      paintAll();
      if (k >= 1) blend = null;
    }

    water.uniforms.uTime.value = t;
    pollen.material.uniforms.uTime.value = t;

    tmp.set(camBase.x + pointer.x * 1.1, camBase.y - pointer.y * 0.5 + scroll * 1.6, camBase.z + scroll * 1.2);
    camera.position.lerp(tmp, 0.045);
    camera.lookAt(look.x, look.y + scroll * 0.9, look.z);

    // Far down the page the scene is only a backdrop → half the frame rate
    if (innerWidth > 0 && innerHeight > 0 && (scroll < 1.2 || (frame++ & 1) === 0)) composer.render();
    if (!reduce) requestAnimationFrame(tick);
  }
  tick();
  if (reduce) addEventListener('lotus-theme', () => setTimeout(() => { blend = null; Object.assign(theme, readTheme()); paintAll(); composer.render(); }, 50));
  document.body.classList.add('webgl-ready');
}
