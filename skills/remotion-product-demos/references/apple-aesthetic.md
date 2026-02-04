# Apple-Keynote Aesthetic Reference

Visual rules for replicating Apple product demo style in Remotion.

## Background Spheres

Soft matte 3D spheres floating with parallax drift.

```
Sphere structure (nested divs):
├── Outer: position absolute, borderRadius 50%, filter blur(2-4px)
├── Body: radial-gradient(circle at highlight%, white 0%, mid 40%, edge 75%, shadow 100%)
│         box-shadow: inset for depth + outer for cast shadow
└── Specular: positioned top-left, radial-gradient white→transparent, blur(4px), rotated
```

### Color Palettes
| Style | Background | Sphere Highlight | Sphere Mid | Sphere Edge |
|-------|-----------|-----------------|-----------|------------|
| light | #e8eaef   | #ffffff          | #d4d8e0   | #bcc2ce    |
| warm  | #e8e2d8   | #ffffff          | #ddd4c6   | #cec2b0    |
| cool  | #dce2ee   | #ffffff          | #c8d0e0   | #b0bcd4    |

### Sphere Placement (1080×1920 canvas)
6 spheres, sizes 340–750px, scattered with some offscreen overlap.
Each has independent drift: `Math.sin((frame * speed + offset) / period) * amplitude`

### Upgrade Path: Three.js
For 9/10 quality, replace CSS spheres with `@remotion/three`:
```tsx
import { ThreeCanvas } from '@remotion/three';
// MeshStandardMaterial with metalness: 0, roughness: 0.8
// PointLight for specular, AmbientLight for fill
// Animate position with useCurrentFrame()
```

## Phone Frame

iPhone 15 Pro proportions and materials.

### Dimensions
- Body: 340×730px at base, scaled 1.55× to fill ~55% canvas width
- Corner radius: 48px outer, 44px screen
- Bezel: 4px metal gradient
- Dynamic Island: 100×28px pill, radius 16px, centered at top

### Material Layers
```
Phone stack (outside in):
├── Grounding shadow (ellipse below phone, radial gradient, blur 14px)
├── 3D transform wrapper (perspective: 1400, rotateY: 8°, rotateX: 2.5°)
├── Metal housing (linear-gradient 145deg: #e6e8ee → #8f95a1)
│   ├── Side buttons (3 left, 1 right) — small rects with gradients
│   ├── Dynamic Island (dark pill + camera dot with radial gradient)
│   └── Multi-layer box-shadow (4 shadows: close→far, plus inset highlights)
├── Screen (white, overflow hidden)
│   ├── Status bar (9:41 + SVG signal/wifi/battery icons)
│   ├── Content area (scenes render here)
│   ├── Home indicator (120×5px bar, 20% opacity, bottom center)
│   └── Glass reflection (125deg linear-gradient, thin bright stripe, pointer-events none)
```

### Float Animation
```tsx
const floatY = Math.sin(globalFrame / 45) * 12;
const floatRotate = Math.sin(globalFrame / 65) * 0.6;
```

## Typography
- Font: Inter via `@remotion/google-fonts/Inter`
- Load: `loadFont("normal", { weights: ["400","500","600","700","800","900"], subsets: ["latin"] })`
- Hierarchy: 30px bold titles, 16px medium body, 12-13px secondary, 11px labels
- Color: #1a1a1a primary, #666-#888 secondary, #999-#aaa tertiary

## Color Usage
- Single accent color (default blue #3B82F6) for: active states, links, filter pills, price text, mic button, + buttons
- Never more than one accent color per video
- White/off-white for cards and surfaces
- Soft shadows: `rgba(0,0,0,0.06)` to `rgba(0,0,0,0.18)` — never harsh black
