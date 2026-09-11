/**
 * The site's only WebGL. A wireframe globe with a particle shell, sized to the
 * hero and nothing more — so the import stays narrow and Three.js tree-shakes
 * down to roughly the renderer plus two geometries.
 *
 * Everything here is deliberately cheap: no lights, no post-processing, no
 * shadow maps, no loaded textures. Line and point materials only.
 */
import {
  BufferAttribute,
  BufferGeometry,
  Color,
  Fog,
  Group,
  IcosahedronGeometry,
  LineBasicMaterial,
  LineSegments,
  PerspectiveCamera,
  Points,
  PointsMaterial,
  Scene,
  WebGLRenderer,
  WireframeGeometry,
} from "three";

export interface GlobeHandle {
  destroy(): void;
}

const ACCENT = 0x00f0ff;
const SKY = 0x38bdf8;

export function mountHoloGlobe(canvas: HTMLCanvasElement): GlobeHandle {
  const renderer = new WebGLRenderer({
    canvas,
    antialias: true,
    alpha: true,
    powerPreference: "low-power",
  });
  // Cap the pixel ratio: a 3x retina canvas triples fragment work for a
  // difference nobody can see on wireframe lines.
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.75));

  const scene = new Scene();
  scene.fog = new Fog(0x08080c, 3.2, 7.5);

  const camera = new PerspectiveCamera(42, 1, 0.1, 20);
  camera.position.set(0, 0, 4.1);

  const globe = new Group();
  scene.add(globe);

  // Wireframe shell.
  const wire = new LineSegments(
    new WireframeGeometry(new IcosahedronGeometry(1.42, 3)),
    new LineBasicMaterial({ color: new Color(ACCENT), transparent: true, opacity: 0.34 })
  );
  globe.add(wire);

  // A sparser inner cage, to read as depth rather than noise.
  const cage = new LineSegments(
    new WireframeGeometry(new IcosahedronGeometry(0.94, 1)),
    new LineBasicMaterial({ color: new Color(SKY), transparent: true, opacity: 0.22 })
  );
  globe.add(cage);

  // Particle shell, distributed evenly over a sphere so it never clumps at
  // the poles the way naive random spherical coordinates do.
  const COUNT = 900;
  const positions = new Float32Array(COUNT * 3);
  for (let i = 0; i < COUNT; i += 1) {
    const u = Math.random() * 2 - 1;
    const theta = Math.random() * Math.PI * 2;
    const r = Math.sqrt(1 - u * u);
    const radius = 1.62 + Math.random() * 0.5;
    positions[i * 3] = r * Math.cos(theta) * radius;
    positions[i * 3 + 1] = u * radius;
    positions[i * 3 + 2] = r * Math.sin(theta) * radius;
  }
  const dustGeometry = new BufferGeometry();
  dustGeometry.setAttribute("position", new BufferAttribute(positions, 3));
  const dust = new Points(
    dustGeometry,
    new PointsMaterial({
      color: new Color(ACCENT),
      size: 0.014,
      transparent: true,
      opacity: 0.55,
      sizeAttenuation: true,
    })
  );
  globe.add(dust);

  // ── sizing ────────────────────────────────────────────────────
  const resize = () => {
    const { clientWidth: w, clientHeight: h } = canvas;
    if (w === 0 || h === 0) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  };
  resize();

  const observer = new ResizeObserver(resize);
  observer.observe(canvas);

  // ── loop, paused whenever the canvas is off screen or the tab is hidden ──
  let frame = 0;
  let running = false;
  let last = performance.now();

  const tick = (now: number) => {
    const dt = Math.min((now - last) / 1000, 0.05);
    last = now;
    globe.rotation.y += dt * 0.12;
    globe.rotation.x = Math.sin(now * 0.00013) * 0.16;
    dust.rotation.y -= dt * 0.045;
    renderer.render(scene, camera);
    frame = requestAnimationFrame(tick);
  };

  const start = () => {
    if (running) return;
    running = true;
    last = performance.now();
    frame = requestAnimationFrame(tick);
  };

  const stop = () => {
    if (!running) return;
    running = false;
    cancelAnimationFrame(frame);
  };

  const visibility = new IntersectionObserver(
    ([entry]) => (entry.isIntersecting ? start() : stop()),
    { threshold: 0 }
  );
  visibility.observe(canvas);

  const onVisibilityChange = () => (document.hidden ? stop() : start());
  document.addEventListener("visibilitychange", onVisibilityChange);

  return {
    destroy() {
      stop();
      observer.disconnect();
      visibility.disconnect();
      document.removeEventListener("visibilitychange", onVisibilityChange);
      scene.traverse((object) => {
        const any = object as unknown as {
          geometry?: { dispose(): void };
          material?: { dispose(): void };
        };
        any.geometry?.dispose();
        any.material?.dispose();
      });
      renderer.dispose();
    },
  };
}
