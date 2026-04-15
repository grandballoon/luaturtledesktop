# GOTCHAS.md — Known Issues, Platform Concerns, and Future Breaking Changes

This document captures platform-specific gotchas, distribution concerns,
and breaking changes that will surface at packaging time. Consult this
before any distribution or cross-platform work.

---

## macOS

### Gatekeeper / Notarization

- Starting with macOS Sequoia (15), Control+Click → Open no longer bypasses
  unsigned apps. Users must go to System Settings → Privacy & Security to
  manually authorize. This is a terrible first experience for students.
- Notarization requires a paid Apple Developer account ($99/year).
- All embedded dylibs (SDL2, Cairo, pixman) must be individually codesigned
  with the same Developer ID and timestamp. One unsigned dylib = Gatekeeper
  rejection on other people's machines.
- The process: codesign with hardened runtime → submit to Apple notary
  service → staple the ticket → distribute as .dmg.
- Debugging Gatekeeper rejections is difficult — error messages are generic.
  Test on a clean machine (not your dev machine) to verify.

### Homebrew-built dependencies

- If you build with Homebrew's SDL2/Cairo on macOS 15, the resulting binary
  may not run on macOS 13 due to minimum OS version encoded in the build.
  For distribution, control your build environment or static link.

### Main thread requirement

- All UI/event processing must happen on the main thread (AppKit/Cocoa
  requirement). This is not a library limitation — it affects SDL2, Cairo,
  and everything else. The REPL integration must work single-threaded.
  "Run the window on a background thread" is not portable on macOS.

### ARM vs. Intel

- Apple Silicon (arm64) and Intel (x86_64) require separate builds or a
  universal binary via `lipo`. Build infrastructure must handle both.

### iCloud Drive xattrs

- iCloud Drive adds persistent extended attributes that can break macOS code
  signing. Build in `/tmp/` or a non-iCloud directory to avoid this.

---

## Windows

### DLL distribution

- If dynamically linking SDL2 and Cairo, you must ship `SDL2.dll` and
  `cairo.dll` (plus `pixman-1.dll` if Cairo isn't statically built)
  alongside the `.exe`. Users who move the `.exe` without the DLLs get
  "SDL2.dll was not found" errors. This is the #1 SDL2 support issue.

### Static linking Cairo on Windows

- Cairo's dependency chain for static linking: pixman (required), optionally
  freetype, libpng, zlib. All must be compiled with matching `/MT` (static
  CRT) settings. Mismatched `/MD` vs `/MT` causes crashes or link errors.
- Define `CAIRO_WIN32_STATIC_BUILD` preprocessor directive in YOUR project
  (not just when building Cairo) or you'll get `__imp__cairo_*` link errors.
- This is significantly more build infrastructure than Raylib's zero-dep
  static linking. Budget time for getting the Windows build right.

### SDL2 WinMain

- SDL2 redefines `main` to `SDL_main` via a macro in `SDL.h` and provides
  its own `WinMain` entry point in `SDL2main.lib`. The `luaturtle` custom
  interpreter must link against `SDL2main.lib` and use `main()`. This is
  standard SDL2 practice but will bite you if you don't know about it.

### SmartScreen

- Unsigned executables trigger "Windows protected your PC" warnings.
  Authenticode code signing certificate costs ~$200-400/year (or free
  via SignPath for open source). Without signing, users must click
  "More info" → "Run anyway."
- SmartScreen also uses reputation — new executables from unknown publishers
  trigger warnings until enough successful installs accumulate.

### Anti-virus false positives

- Self-contained executables that open windows, hook input, or embed
  interpreters are commonly flagged by consumer anti-virus as suspicious.
  This is more likely with statically linked executables.

---

## Linux

### glibc version constraint

- A binary compiled on Ubuntu 24 may not run on Ubuntu 20 due to newer
  glibc requirement. Standard fix: build on the oldest distro you support,
  or use a Docker container with an older base image for release builds.
- AppImage bundles its own shared libraries, mostly solving this.

### AppImage + Cairo font issue

- Cairo links against system fontconfig for font discovery. If fontconfig
  isn't configured correctly in the AppImage, `write()` may fail to find
  fonts. This is a known AppImage packaging gotcha for Cairo-based apps.
  Test `write("hello")` on a clean system after packaging.

### Wayland vs. X11

- SDL2 transparently handles both. Not a differentiator, but some Wayland
  compositors have quirks with older SDL2 versions. Use SDL2 2.28+ for
  best Wayland support.

---

## Cross-Platform: Font Rendering

This is the most likely source of visual inconsistency across platforms.

Cairo's text rendering depends on which font backend it was compiled with:
- **FreeType** (optional, must be linked): Consistent rendering across all
  platforms. Same hinting, same glyph shapes. Requires bundling FreeType.
- **Native backends**: CoreText on macOS, Win32 on Windows, fontconfig on
  Linux. Native-looking text but different rendering per platform.

For turtle graphics, text (from `write()`) is rarely the star — geometry is.
Native-per-platform is probably fine. But decide consciously:
- If you build Cairo with FreeType on macOS/Linux but without it on Windows,
  `write()` output will look different across platforms.
- If you want consistency, build with FreeType everywhere (one more dep).
- If you want native feel, accept the differences.

---

## Web (Future)

### SharedArrayBuffer requirements

- The Web Worker + `Atomics.wait` architecture (WebTigerPython pattern)
  requires specific HTTP headers:
  ```
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  ```
- These headers must be set by the web server. On Cloudflare Pages (current
  host), this requires a `_headers` file.
- Without these headers, `SharedArrayBuffer` is unavailable and the entire
  synchronous-execution-in-worker architecture fails silently.

### Atomics.wait main thread restriction

- `Atomics.wait` does NOT work on the main thread — only in Web Workers.
  This is fine for the architecture (Lua runs in the worker). But it means
  the current `index.html` approach (Lua on main thread with action queue)
  cannot be incrementally upgraded. The web port is a clean break to a
  two-thread architecture.

### Browser compatibility

- `SharedArrayBuffer` is available in all modern browsers (Chrome, Firefox,
  Safari, Edge). But some corporate/school network proxies strip the
  required CORS headers, silently breaking the feature. Test on school
  networks before deploying to classroom use.

---

## SDL2-Specific

### SDL_PollEvent blocks during window drag/resize on Windows

- While a user is actively dragging or resizing the window, `SDL_PollEvent`
  can block. This is a Windows OS behavior, not an SDL bug. Animation will
  stall during resize. Acceptable for turtle graphics.

### SDL2 vs. SDL3

- SDL3 is the actively developed version. SDL2 is in maintenance mode.
  Starting with SDL2 is fine (stable, well-documented). A future migration
  to SDL3 is likely within a few years. API changes exist but are
  manageable.

### Premultiplied alpha

- Cairo uses premultiplied alpha. SDL2 surfaces use unpremultiplied (straight)
  alpha. When blitting Cairo's output to an SDL2 surface/texture, you must
  handle the conversion. For turtle graphics where the final output is
  opaque (alpha compositing happens in Cairo, presented result is opaque
  to SDL2), this is a non-issue. If you ever need per-pixel alpha on the
  SDL2 surface, flush the Cairo surface first and handle the conversion
  in the C binding.

---

## Cairo-Specific

### Performance slow paths

- Cairo's image surface (CPU rendering) is the most portable but not
  hardware-accelerated. For turtle graphics this is fine — the workload
  is light (hundreds to low thousands of segments, not millions).
- The common performance pitfall: creating new Cairo surfaces frequently.
  Reuse surfaces. The persistent canvas pattern (one offscreen surface,
  drawn to incrementally) avoids this.

### Cairo + pixman dependency

- Cairo always requires pixman (its pixel manipulation library). When
  packaging, pixman must be bundled or statically linked alongside Cairo.
  On macOS/Linux this is handled by package managers. On Windows it's
  part of the Cairo static build process.

---

## Lua-Specific

### colors.lua lazy loading

- `core.lua` loads `turtle.colors` via `require("turtle.colors")` inside
  color-parsing functions. This means `package.path` must include the
  correct path at runtime. In tests from the project root, this is
  `./turtle/?.lua`. In the distributed binary, colors.lua must be bundled
  where `require` can find it.
- If colors.lua isn't findable, named colors (`pencolor("red")`) silently
  fail — the `require` is inside a function, so the error only surfaces
  when a student actually uses a color name.

### __gc sentinel for window-on-exit

- The `__gc` sentinel trick (keeping the window open if the script exits
  without calling `done()`) relies on Lua's GC finalizer running during
  `lua_close`. This works with the standard `lua` interpreter and the
  custom `luaturtle` binary. If anyone runs the library with a non-standard
  Lua host, finalizer behavior may differ.

### `goto` is reserved

- Lua 5.4 reserves `goto` as a keyword. The user-facing alias is `setpos()`.
  Python turtle's `goto()` cannot be used. This is documented but will
  confuse students coming from Python. Consider a helpful error message
  if someone tries to use `goto` as a function call (the Lua parser will
  catch it, but the error message will be cryptic).
