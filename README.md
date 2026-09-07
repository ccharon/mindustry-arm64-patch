# Mindustry SDL backend for linux/aarch64

Mindustry refuses to start on arm64 Linux:

    Couldn't load shared library 'libsdl-arcarm64.so' for target: Linux, 64-bit
    Unable to read file for extraction: libsdl-arcarm64.so

Every Arc native lib is in the jar for arm64 (`libarcarm64.so`,
`libarc-freetypearm64.so`, `libarc-filedialogsarm64.so`) only the SDL backend
is missing.

This directory builds that one missing JNI wrapper and injects it into the jar.

## What you need

- **The `Mindustry.jar`** This kit patches that jar
- A JDK (headers included, a JRE is not enough), `gcc`/`g++`, `git`, `curl`,
  `zip`/`unzip`, `nm`, and SDL2 development files (`sdl2-config` on `PATH`).
- Network access: Arc is cloned, Gradle bootstraps itself and pulls GLEW 2.2.0.

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
    GLEW=egl        build against EGL instead of GLX (see below)

The Arc commit matters: the wrapper is generated from Arc's `SDL.java` /
`SDLGL.java`, so it has to come from the commit your jar was built against.
`make` looks it up from the `v<build>` release tag at <https://github.com/Anuken/Mindustry>. 
`check` then confirms the result against the jar's own classes and refuses 
to patch if a native method is missing. 

## X11 or Wayland

GLEW binds to one GL loader at build time, so the build has to match the video
driver SDL ends up on. SDL2 tries its x11 driver before wayland, so it picks
x11 whenever an X display is reachable, on an X session as well as through
XWayland.

The default build (`GLEW=glx`) runs without any setting:

    java -jar Mindustry.jar

An EGL build on the same x11 driver needs an EGL context instead of a GLX one:

    SDL_VIDEO_X11_FORCE_EGL=1 java -jar Mindustry.jar

For a native Wayland window, set `SDL_VIDEODRIVER` to wayland:

    make GLEW=egl
    SDL_VIDEODRIVER=wayland java -jar Mindustry.jar

### Example desktop entry for Wayland (egl build)

`GLEW=egl` build. `SDL_VIDEO_WAYLAND_WMCLASS` sets the window class, which SDL
otherwise takes from `argv[0]`, here `java`. Without it the desktop shell cannot
match the window to this launcher.

```desktop
[Desktop Entry]
Type=Application
Name=Mindustry
Icon=/path/to/mindustry.png
Exec=env SDL_VIDEODRIVER=wayland SDL_VIDEO_WAYLAND_WMCLASS=Mindustry java -jar /path/to/Mindustry.jar
StartupWMClass=Mindustry
Terminal=false
```

### Example desktop entry for X11 (glx build)

```desktop
[Desktop Entry]
Type=Application
Name=Mindustry
Icon=/path/to/mindustry.png
Exec=env SDL_VIDEO_X11_WMCLASS=Mindustry java -jar /path/to/Mindustry.jar
StartupWMClass=Mindustry
Terminal=false
```

## If something looks wrong

`GLEW failed to initialize` means the build and the video driver disagree.
`Unknown error` is a GLX build on an EGL context, `Missing GL version` an EGL
build on a GLX context.

The build is loud. The `-Wint-to-pointer-cast` and unused-variable warnings from
`SDLGL.cpp` are normal jnigen output and appear in the x86 build too. What
matters is `make check`, which `make patch` runs for you.

## Tested on

    Gentoo Linux, aarch64 (Apple M2, Asahi)
    Temurin JDK 25.0.4
    gcc 15.3.0
    SDL2 2.32.8
    Mindustry 159.7, Arc c4c3707ae8

Both build variants, GLX on XWayland and EGL on Wayland.
