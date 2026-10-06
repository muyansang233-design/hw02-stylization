# Paint Poisson distribution

`Assets/Shaders/SG_Paint_PoissonDisk.shadersubgraph` wraps the file-mode
`PaintPoissonDisk` function in `Assets/Shaders/PaintPoissonDisk.hlsl`.
`SG_Paint_BrushDistribution` uses it twice, with Seed 0 and Seed 1.
The layer-color subgraph keeps its existing interface. The main material exposes
**Brush Size Layer 1** and **Brush Size Layer 2**, forwarded through Brush
Distribution to each Poisson instance. Both default to 1, with sliders from 0.1
to 2. They change each brush's footprint independently of distribution density;
each control applies uniformly to every brush in that layer.

## Inputs

- **UV**: mesh UV coordinates; wired to UV0 in Brush Distribution.
- **Density**: scales the UV domain. Higher values give more, smaller brushes.
  Zero/negative values produce zero Coverage.
- **Seed**: integer-valued. Even/odd seeds select one of two independent point
  sets; each seed also translates the pattern and changes per-brush variation.
- **Brush Size**: width of the brush in density-scaled coordinates; default 1.
- **Rotation Degrees**: maximum rotation either side of zero; default 30.

Outputs are Brush UV, Random Value, Color Choice (0/1), and Coverage.
Distribution multiplies the inverted brush texture mask by Coverage to suppress
texture clamp streaks outside the rotated brush square.

## Sampling and limits

Point sets are baked using Bridson sampling with periodic distance checks, 30
candidate attempts, tile width 4, and minimum separation 0.8. Each layer contains
14 points per tile. Minimum spacing applies within each layer, not across layers.
The tile repeats every `4 / Density` UV units. This is a periodic Poisson point
set, not an infinitely nonrepeating procedural point process.

Each layer evaluates the nearest center. Large overlapping brushes can be clipped
at nearest-center boundaries; brushes within the same layer are not accumulated.
Runtime shaders only search the baked sets; they do not perform rejection sampling.

Runtime shader code is maintained directly in `Assets/Shaders/PaintPoissonDisk.hlsl`.
It includes the generated point tables from `Assets/Shaders/PaintPoissonPoints.hlsl`.
The Python script only generates that data file; it never overwrites runtime shader code.
Unity rendering and builds do not require Python.

Regenerate the point tables from the project root with
`python Tools/generate_paint_poisson.py` (standard library only).
Algorithm reference: https://www.cs.ubc.ca/~rbridson/docs/bridson-siggraph07-poissondisk.pdf

Validation: both float/half functions compile with Direct3D 11 `ps_5_0`;
point separation, periodic lookup, graph ports, and the existing Brush Distribution
interface were checked. Unity import and rendered scene appearance still require
verification in the Editor.

## Third layer: ring-centered stamps

`PaintRingStamps.hlsl` is used by MAT_Paint's third layer. It checks every nearby
Poisson candidate center against the signed-lighting band, samples a complete
rotated brush for each accepted center, and combines overlaps with
`1 - (1 - accumulated) * (1 - stamp)`. The resulting pixels are not clipped by
the ring. A stamp centered inside the band may extend beyond it.

The shader estimates lighting at candidate centers from the fragment's UV and
lighting derivatives. This is exact for an affine lighting field and approximate
on curved surfaces; it is not a UV-space lighting-mask bake or global resampling.
Sharp normal changes and UV seams can cause inaccurate acceptance. Degenerate UV
derivatives disable the third layer. An exact arbitrary-surface implementation
would require a sampled UV-space lighting/normal field or mesh-side sampling.

Ring Brush Density defaults to 12, Ring Brush Size to 1.5 (maximum 2), and Ring
Width controls the permitted center band on either side of Color Boundary. Both
original layers retain their existing sampling. Texture samples use explicit
gradients for mip selection inside the candidate loop. This third layer requires
fragment derivatives and can cost more texture samples than a single brush layer.

Ring colors are visible nodes in MAT_Paint: Ring Brush Color and the existing
AnalogousAngle property feed the reused AnalogousColors custom function; its two
outputs feed a Lerp controlled by PaintRingStampsColors.ColorMix. Each center has
a stable binary random color choice. ColorMix tracks alpha-over contributions so
overlapping stamps blend correctly when the final Lerp applies the combined mask.
The stamp function only computes mask/color weights; analogous color generation
and RGB blending stay in graph nodes. Legacy one-output entry points remain valid.
