---
name: remotion-product-demos
description: Create Apple-keynote-quality product demo videos with Remotion. Covers glass phone mockups, floating 3D spheres, typing animations, card UIs, ripple effects, and smooth scene transitions. Use when asked to create product demos, app showcase videos, UI walkthrough animations, or "glass phone" style content. Triggers on "product demo video", "app demo", "glass phone", "keynote-style video", "phone mockup animation", "GlassPhoneDemo".
---

# Remotion Product Demo Videos

Build production-quality product demo videos in the Apple-keynote style using Remotion.

## Quick Start

Project: `~/Projects/tails-video/`
Template: `src/templates/GlassPhoneDemo.tsx`

```bash
cd ~/Projects/tails-video
npx remotion render src/index.ts GlassPhoneDemo out/demo.mp4 \
  --codec=h264 --crf=18
```

Custom content via `--props`:
```bash
npx remotion render src/index.ts GlassPhoneDemo out/custom.mp4 \
  --props='{"scenes":[{"type":"hero","durationInSeconds":3}],"brand":{"name":"YourBrand"}}'
```

## Template: GlassPhoneDemo

### Schema (Zod)

```typescript
{
  scenes: Array<{
    type: 'hero' | 'voice' | 'typing' | 'cards' | 'detail' | 'dropdown' | 'endCard',
    title?: string,
    subtitle?: string,
    text?: string,           // typing scenes
    cards?: Array<{ name, category, detail?, emoji? }>,  // cards scene
    items?: Array<{ name, price? }>,                      // detail scene
    options?: Array<{ label, sublabel?, icon? }>,          // dropdown scene
    durationInSeconds: number  // default 3
  }>,
  accentColor: string,       // default '#3B82F6'
  bgStyle: 'light' | 'warm' | 'cool',
  deviceAngle: number,       // default 8 (degrees of Y rotation)
  brand?: { name: string, tagline?: string }
}
```

### Scene Types

| Type | Visual | Key Props |
|------|--------|-----------|
| hero | Phone with "Tap to type" + action buttons | — |
| voice | Mic icon + continuous ripple rings | — |
| typing | Character-by-character text with cursor | `text` |
| cards | Staggered card list (restaurant-style) | `cards[]`, `title` |
| detail | Filter pills + item grid with prices | `items[]`, `title`, `subtitle` |
| dropdown | Glassmorphic option picker | `options[]`, `text` |
| endCard | Phone fades, brand appears centered | — (uses top-level `brand`) |

### Recommended Scene Flow

A typical demo follows: **hero → voice → typing → results → detail → typing → dropdown → endCard**

Duration guide: hero 3s, voice 2s, typing 3s per command, cards/detail 4s, dropdown 3s, endCard 2s.

## Visual Style Rules

Read [references/apple-aesthetic.md](references/apple-aesthetic.md) for the full style guide.

Key rules:
- **Background:** Soft 3D spheres with radial gradients, specular highlights, and cast shadows
- **Phone:** iPhone-style with metal bezel gradient, Dynamic Island, side buttons, home indicator, glass reflection overlay, grounding shadow
- **Colors:** Monochrome whites/grays + single configurable accent color
- **Motion:** Everything via `useCurrentFrame()` + `spring({damping: 200})`. Zero CSS animations.

## Animation Patterns

Read [references/animation-patterns.md](references/animation-patterns.md) for spring configs, timing formulas, and easing patterns.

Key patterns:
- **Entrance:** `spring({ frame: sceneFrame, fps, config: { damping: 200 } })` → opacity + translateY
- **Stagger:** delay each item by `i * 6` frames
- **Float:** `Math.sin(globalFrame / 45) * 12` for gentle drift
- **Typing:** `Math.floor((sceneFrame - delay) * 0.55)` chars revealed
- **Ripple:** Continuous via modulo: `(frame + ring * offset) % cycleDuration`
- **Cross-fade:** Overlap scenes with `-transitionFrames` to `0` fade-in, `dur - transitionFrames` to `dur` fade-out

## Improvement Backlog

Current status: **good, not perfect**. Known gaps:

1. **Three.js background spheres** — CSS radial-gradient spheres cap at ~7/10. Real `@remotion/three` with proper lighting = 9/10
2. **Real imagery** — colored placeholder blocks → Unsplash/Pexels food photos via `<Img>` component
3. **Variable typing speed** — faster on common words, slight pauses on spaces
4. **Screen glow** — subtle ambient light bleeding from phone screen edges
5. **Constants-first pattern** — extract all magic numbers to named constants at file top (Remotion official recommendation)

## Creating New Templates

When building a new product demo template:

1. **Analyze reference video** frame-by-frame (extract at 1s intervals)
2. **Identify visual components:** background, device, content, transitions
3. **Define Zod schema** with scene types and configurable props
4. **Build components bottom-up:** background → device frame → scenes → transitions
5. **Test at each step** — render individual frames before full video
6. **QA with vision model** — extract frames, rate quality, iterate

Follow Remotion rules strictly: read `skills/remotion-best-practices/` rule files.
