# Metal + SpriteKit shaders

## 11. Metal + SpriteKit

Metal absolutely works with SpriteKit — SpriteKit *is* a Metal renderer. Since iOS 12 the OpenGL path is gone and every SKView renders through Metal (the legacy `PrefersOpenGL` Info.plist flag only mattered pre-iOS 12 / on old simulators, which caused GLSL-vs-Metal shader syntax mismatches). Four integration tiers, shallow to deep:

**Tier 1 — `SKShader` fragment shaders (the 95% case).** Attach a `.fsh` fragment shader to any `SKSpriteNode`, `SKEffectNode`, `SKShapeNode` (`fillShader`/`strokeShader`), emitter, or tile map. Written in GLSL-style syntax that SpriteKit translates to Metal at runtime. Key mechanics:
- Built-in inputs: `u_time`, `u_texture`, `v_tex_coord`, plus custom data via `SKUniform` (global per-shader) and `SKAttribute`/`SKAttributeValue` (per-node — critical for sharing one compiled shader across many nodes).
- Compile shaders **once** at load time and reuse; creating `SKShader` per node per frame recompiles and stalls.
- Batching caveat still applies: each shaded node is its own draw call. Full-screen/layer effects go on one `SKEffectNode` wrapper.
- Steal from the two shader libraries above (ShaderKit for polished game effects — outline, glitch, water, pixelate, emboss; eleev's sandbox for heavier stuff — CRT, raymarching, procedural noise).

**Tier 2 — `SKWarpGeometryGrid` + geometry warps.** GPU mesh deformation (flag waves, jelly hits, page turns) without touching shaders; animatable via `SKAction.warp(to:duration:)`.

**Tier 3 — Core Image on `SKEffectNode`.** Any `CIFilter` (bloom, blur, displacement) applied to a node subtree; CI itself executes on Metal. Combine with `shouldRasterize` for static content.

**Tier 4 — `SKRenderer` (iOS/tvOS 11+, WWDC17 session 609).** Replaces SKView entirely: you drive `update(atTime:)` and `render(withViewport:commandBuffer:renderPassDescriptor:)` yourself inside your own `MTKView`/`CAMetalLayer` pipeline. This unlocks:
- SpriteKit scene rendered **to a texture** used anywhere in a Metal scene (Apple's demo: a playable SpriteKit game mapped onto a 3D arcade cabinet with a Metal CRT post-shader).
- Custom post-processing chains: render scene → offscreen texture → your MSL compute/fragment passes → drawable.
- Mixing SpriteKit HUD/2D layers into a Metal or SceneKit game with exact control of render order and timing.
- Full Metal Shading Language (real MSL, not the GLSL dialect) for everything outside the SKShader boundary.

Also relevant: `SKMutableTexture` for CPU/GPU-generated texture data, and `SK3DNode`/SceneKit interop for 2.5D (SpriteKit scene as SceneKit material and vice versa).

**Practical guidance for a skill:** default to Tier 1–3; they cover essentially all 2D game juice. Reach for `SKRenderer` only for engine-level needs (custom post-FX pipeline, SpriteKit-in-3D, deterministic render timing) — you give up SKView conveniences (gesture/hit-testing plumbing, automatic display link) and own them yourself.

