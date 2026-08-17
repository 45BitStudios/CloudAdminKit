# Physics & collision

## 4. Physics & collision

- **Category bitmasks as an `OptionSet` or `UInt32` enum with shifted bits** (`1 << n`). All three surveyed games do a variant of this (`Contact`/`PhysicsCategory` type). Keep categories, collision masks, and contact-test masks in one file; document the collision matrix in a comment.
- Distinguish `collisionBitMask` (physical response) from `contactTestBitMask` (callback). Most arcade collectibles want contact-test only, with `collisionBitMask = 0`.
- In `didBegin(_ contact:)`, **normalize body ordering** (sort by category value) before branching, and defer node removal/scene mutations to the end of the physics pass — mutating mid-callback with both bodies in flight causes double-hit bugs. Guard against nodes already removed (`node.parent != nil`).
- **Shape fidelity vs. cost:** circles < rectangles < polygon paths < texture-alpha bodies. Terranous's "pixel-perfect" `CGMutablePath` bodies (built once, cached in a texture singleton and reused for every spawn) is the right idea: precompute paths once, never per-spawn, and never use `SKPhysicsBody(texture:)` in hot spawn paths.
- Edge-loop bodies (`edgeLoopFrom:`) for screen/world bounds; give the container node, not the scene, the edge body if gameplay area ≠ full screen.
- For platformers, consider *not* using SKPhysics for character movement at all — glide implements its own kinematic collision against a tile map (`collisionTileMapNode`) because SKPhysics is poor at precise platformer feel. SKPhysics is great for projectiles, debris, and ragdoll; bespoke kinematics win for tight character control.

