# TODO

- Document `:dependency_cycle` in `docs/src`. The metric name belongs in the
  `suppression.md` list a directive may name, the rule wants a section beside `:scattered`
  in `cohesion.md`, and `languages.md` should say it needs a linkage query like the other
  cross-file passes.
- Write up what cross-file resolution reaches per language. The investigation is done: Java
  and PHP expose only types across the boundary, so their unit graph carries no cross-file
  edge and `:misplaced`, `:scattered` and `:incoherent_package` stay silent, which is the
  type-and-dispatch line holding rather than a gap. JavaScript reads ES modules only, so a
  CommonJS corpus (express, lodash) resolves nothing, and Ruby reads only
  `require_relative`, so a conventional library (sinatra) resolves nothing either. The
  TypeScript `.js`-specifier gap is fixed. What is left is saying all of this in
  `languages.md`, since a rule that stays quiet for want of linkage currently reads as a
  clean report.
