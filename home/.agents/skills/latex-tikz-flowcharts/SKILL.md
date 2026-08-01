---
name: latex-tikz-flowcharts
description: Create polished flowcharts, architecture diagrams, process maps, data pipelines, and system diagrams as vector PDFs using LaTeX with TikZ/PGF and the pdfTeX engine. Use this skill whenever a user asks to create or substantially revise a flowchart or a standalone technical diagram, unless the user explicitly requires another format or tool.
compatibility: Requires pdflatex from TeX Live, pdftoppm from Poppler, and an image-viewing tool.
---

# LaTeX TikZ Flowcharts

Create diagrams as maintainable `.tex` source files and compile them into vector PDFs.
Treat the bundled examples as visual quality references, not as content templates.

## Reference selection

Read [references/example-catalog.md](references/example-catalog.md) before designing the diagram.
Render and inspect the one or two examples whose layout patterns best match the requested information.
Do not load every example when a smaller relevant set is enough.

## Workflow

1. Identify the diagram's main message, reading order, boundaries, actors, states, and exceptional paths.
2. Choose the closest bundled reference pattern.
3. Build the source with LaTeX and TikZ/PGF.
4. Use a tightly cropped standalone page unless the diagram belongs inside a larger document.
5. Compile with `pdflatex`, which runs the LaTeX format on the pdfTeX engine.
6. Render the resulting PDF to PNG and inspect it visually.
7. Iterate until the diagram is clear, balanced, and free of rendering defects.
8. Deliver both the editable `.tex` source and the final `.pdf`.

## TikZ foundations

Prefer `\documentclass[tikz,border=8pt]{standalone}` for standalone diagrams.
Use TikZ libraries such as `arrows.meta`, `positioning`, `fit`, `calc`, `shapes.geometric`, and `backgrounds` when they improve clarity.
Define reusable styles for nodes, groups, stores, arrows, annotations, and semantic colors.
Use relative positioning and named anchors instead of manually tuning every coordinate.
Keep color meaning stable across the whole diagram.
Use restrained fills, clear borders, and a small number of accent colors.
Keep primary paths visually dominant and render secondary or exceptional paths with distinct line styles.

## Compilation and inspection

Compile from the directory containing the source:

```sh
pdflatex -interaction=nonstopmode -halt-on-error -file-line-error diagram.tex
```

Render the PDF for visual inspection:

```sh
pdftoppm -png -r 180 -singlefile diagram.pdf diagram-preview
```

Inspect the rendered PNG at full resolution.
Recompile after every meaningful source change and inspect the latest render.

## Quality standard

Match the bundled examples on the qualities that make them effective:

- A clear left-to-right or top-to-bottom reading path
- Strong grouping through boundaries and restrained background fills
- Consistent typography, node padding, corner radii, and arrow treatment
- Labels placed close to the paths or objects they explain
- Enough whitespace to distinguish stages without making the diagram sparse
- Short explanatory notes where the visual alone would be ambiguous
- Vector text and shapes with embedded fonts

Reject a result if text is clipped, overlaps another element, becomes illegible at normal viewing size, or relies on crossing arrows that could be routed more clearly.
Reject a result if the page has excessive empty space or the composition is visibly unbalanced.
Do not substitute Mermaid, Graphviz, browser screenshots, or raster drawing tools unless the user explicitly asks for them.

## Deliverables

Keep the source and output names aligned, such as `data-flow.tex` and `data-flow.pdf`.
Preserve the `.tex` source so future agents can revise the diagram without reverse-engineering the PDF.
Keep temporary `.aux`, `.log`, and preview files out of the final deliverable unless the user requests them.
