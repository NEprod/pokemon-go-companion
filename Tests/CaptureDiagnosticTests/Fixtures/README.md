# Private screen references

`ScreenReferences/` is an optional, ignored local directory containing personal reference screenshots. It is excluded from SwiftPM resources and must not be committed. Tests use it when present, or use `GO_COMPANION_SCREEN_REFERENCES_DIR` to select an external directory with the same category folders. When the directory is absent, screenshot-dependent tests are skipped; synthetic capture/classifier/stabilizer tests still run.

Exact classifier RGB archives remain outside the repository. Set `GO_COMPANION_PRIVATE_RGB_DIR` to enable their optional replay tests. Neither fixture source is uploaded or copied into the test bundle.
