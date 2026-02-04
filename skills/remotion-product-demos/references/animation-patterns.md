# Animation Patterns Reference

All animations driven by `useCurrentFrame()`. CSS animations/transitions/keyframes FORBIDDEN.

## Spring Config Presets

```tsx
// Smooth, no bounce (default for UI elements)
spring({ frame, fps, config: { damping: 200 } })

// Gentle settle (cards, dropdowns)
spring({ frame, fps, config: { damping: 200, mass: 1.2 } })

// Snappy (small elements, pills)
spring({ frame, fps, config: { damping: 200, stiffness: 200 } })
```

## Common Patterns

### Entrance (opacity + slide)
```tsx
const enter = spring({ frame: sceneFrame, fps, config: { damping: 200 } });
// Apply:
style={{
  opacity: enter,
  transform: `translateY(${(1 - enter) * 20}px)`,
}}
```

### Staggered List
```tsx
cards.map((card, i) => {
  const s = spring({
    frame: sceneFrame - 8 - i * 6,  // 8 frame delay + 6 frame stagger
    fps,
    config: { damping: 200 },
  });
  return <div style={{ opacity: s, transform: `translateY(${(1 - s) * 40}px)` }} />;
});
```

### Typing Animation
```tsx
const charsPerFrame = 0.55;
const startDelay = 8;
const charsToShow = Math.min(
  text.length,
  Math.max(0, Math.floor((sceneFrame - startDelay) * charsPerFrame))
);
const displayText = text.slice(0, charsToShow);

// Cursor blink
const cursorVisible = Math.floor(sceneFrame / 15) % 2 === 0;
const showCursor = charsToShow < text.length || cursorVisible;
```

### Continuous Ripple (for voice/listening)
```tsx
const ringCount = 5;
const cycleDuration = 45;

Array.from({ length: ringCount }).map((_, ring) => {
  const phase = (sceneFrame + ring * (cycleDuration / ringCount)) % cycleDuration;
  const progress = phase / cycleDuration;
  const scale = interpolate(progress, [0, 1], [0.5, 3.2]);
  const opacity = interpolate(progress, [0, 0.1, 0.6, 1], [0, 0.4, 0.1, 0]);
  // ...
});
```

### Float/Drift (background elements + phone)
```tsx
// Slow organic motion — different period for each axis
const dx = Math.sin((frame * speed + offset) / 55) * amplitude;
const dy = Math.cos((frame * speed + offset) / 62) * amplitude;
```

### Cross-Fade Between Scenes
```tsx
const transitionFrames = 10;

// Fade in from before scene start (enables overlap)
const fadeIn = interpolate(sf, [-transitionFrames, 0], [0, 1], {
  extrapolateLeft: 'clamp', extrapolateRight: 'clamp',
});
// Fade out at scene end
const fadeOut = interpolate(sf, [dur - transitionFrames, dur], [1, 0], {
  extrapolateLeft: 'clamp', extrapolateRight: 'clamp',
});
const opacity = Math.min(fadeIn, fadeOut);
```

### Phone Exit (end card)
```tsx
// Phone shrinks and fades
const phoneScale = interpolate(ef, [0, 30], [1.55, 1.0], {
  extrapolateRight: 'clamp',
  easing: Easing.out(Easing.cubic),
});
const phoneOpacity = interpolate(ef, [8, 35], [1, 0], {
  extrapolateLeft: 'clamp', extrapolateRight: 'clamp',
});

// Brand text springs in after phone fades
const brandSpring = spring({ frame: ef - 15, fps, config: { damping: 200 } });
```

## Timing Guidelines

| Scene Type | Recommended Duration | Animation Start |
|------------|---------------------|-----------------|
| hero       | 3s (90 frames)      | Buttons stagger at frame 8 + i*4 |
| voice      | 2s (60 frames)      | Ripple starts immediately |
| typing     | 2-4s depends on text length | Delay 8 frames before typing starts |
| cards      | 3-4s (90-120 frames) | Cards stagger at frame 8 + i*6 |
| detail     | 3-4s (90-120 frames) | Pills at frame 4 + i*2, items at frame 6 + i*5 |
| dropdown   | 2-3s (60-90 frames) | Card enters at frame 12, options at frame 16 + i*4 |
| endCard    | 2s (60 frames)      | Phone fades frames 0-35, brand at frame 15 |

## Anti-Patterns

- ❌ CSS `animation`, `transition`, `@keyframes`, Tailwind `animate-*`
- ❌ `Math.random()` — use `random('seed')` from remotion
- ❌ `setTimeout`, `setInterval` — use frame-based timing
- ❌ Hard cuts between scenes — always cross-fade
- ❌ Linear interpolation for entrances — always spring physics
