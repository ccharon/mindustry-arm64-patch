# Mindustry SDL backend for linux/aarch64

Mindustry refuses to start on arm64 Linux:

    Couldn't load shared library 'libsdl-arcarm64.so' for target: Linux, 64-bit
    Unable to read file for extraction: libsdl-arcarm64.so

Every other Arc native is in the jar for arm64 (`libarcarm64.so`,
`libarc-freetypearm64.so`, `libarc-filedialogsarm64.so`) — only the SDL backend
is missing. The gap is in Arc, not in your build: `backends/backend-sdl/build.gradle`
declares `addLinux(x64, x86)`, so the published artifact
`com.github.Anuken.Arc:backend-sdl` does not contain the blob either.

This directory builds that one missing JNI wrapper and injects it into a jar.

## What you need

- **The `Mindustry.jar` you downloaded.** This kit patches that jar, it does not
  build the game and does not need its sources.
- A JDK (headers included, a JRE is not enough), `gcc`/`g++`, `git`, `curl`,
  `zip`/`unzip`, `nm`, and SDL2 development files (`sdl2-config` on `PATH`).
- Network access on the first run: Arc is cloned, Gradle bootstraps itself and
  pulls GLEW 2.2.0.

`make tools` lists whatever is missing.

## Usage

Put `Mindustry.jar` next to the `Makefile` and run:

    make

It checks the tools, works out which Arc commit your jar was built against,
builds `libsdl-arcarm64.so` and injects it into the jar, keeping a backup as
`Mindustry.jar.orig`. Then start the game as usual.

Other targets:

    make check      does the built .so match the jar?
    make unpatch    take the .so back out of the jar
    make archash    print the Arc commit your jar needs
    make clean      drop build products (distclean: everything)
    JAR=<path>      patch a jar somewhere else
    ARCHASH=<hash>  force an Arc commit

The Arc commit matters: the wrapper is generated from Arc's `SDL.java` /
`SDLGL.java`, so it has to come from the commit your jar was built against. It is
not stored in the jar, so `make` looks it up from the `v<build>` release tag at
<https://github.com/Anuken/Mindustry>. `check` then confirms the result against
the jar's own classes and refuses to patch if a native method is missing — that,
not the hash, is what settles it. If you built the jar yourself, the tag lookup
can point at a different commit; pass `ARCHASH=` from your `gradle.properties`.

## If something looks wrong

- **The x86-64 `libSDL2.so` in the jar is not a second problem.** It looks like
  one. Arc pre-loads it via `System.load()` on Linux and swallows the failure in
  `catch(Throwable)`; the wrapper links dynamically against
  `libSDL2-2.0.so.0` and gets the system SDL2. If the game starts and reports
  your system's SDL version, that is working as intended.
- **The build is loud.** `-Wint-to-pointer-cast` and unused-variable warnings out
  of `SDLGL.cpp` are normal jnigen output and appear in the x86 build too. What
  matters is `make check`, which is run for you by `make patch`.
