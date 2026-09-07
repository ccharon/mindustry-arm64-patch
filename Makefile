# Puts Arc's SDL backend for linux/aarch64 (libsdl-arcarm64.so) into a Mindustry
# jar. Upstream does not ship that file: Arc's backends/backend-sdl/build.gradle
# only declares addLinux(x64, x86).
#
# Drop Mindustry.jar next to this Makefile and run:
#
#     make
#
# That checks the tools, works out which Arc commit the jar was built against,
# builds the JNI wrapper and injects it (keeping a backup as Mindustry.jar.orig).
# Override with JAR=<path> or ARCHASH=<arc commit> if you need to.

JAR      ?= $(dir $(lastword $(MAKEFILE_LIST)))Mindustry.jar
LIB      := libsdl-arcarm64.so
WORK     ?= work
ARC_REPO ?= https://github.com/Anuken/Arc.git
MDT_RAW  ?= https://raw.githubusercontent.com/Anuken/Mindustry
ARCHASH  ?=

.PHONY: patch check unpatch archash tools help clean distclean
.DEFAULT_GOAL := patch

help:
	@echo 'make            build the backend and patch $(notdir $(JAR))'
	@echo 'make check      does the built .so match the jar?'
	@echo 'make unpatch    take the .so back out of the jar'
	@echo 'make archash    print the Arc commit the jar needs'
	@echo 'make clean      drop build products (distclean: everything)'
	@echo
	@echo 'JAR=<path>      patch another jar than ./Mindustry.jar'
	@echo 'ARCHASH=<hash>  force an Arc commit (self-built jars)'

tools:
	@ok=0; for t in git gcc g++ javac javap nm curl zip unzip sdl2-config; do \
	    command -v $$t >/dev/null || { echo "missing tool: $$t"; ok=1; }; \
	done; \
	[ -d "$$(dirname $$(dirname $$(readlink -f $$(command -v javac 2>/dev/null) 2>/dev/null)) 2>/dev/null)/include" ] \
	    || { echo "missing: JDK headers - a JRE is not enough"; ok=1; }; \
	[ -f '$(JAR)' ] || { echo "no Mindustry.jar here. Put one next to the Makefile, or pass JAR=<path>."; ok=1; }; \
	exit $$ok

unpatch:
	zip -qd '$(JAR)' $(LIB) && echo "removed $(LIB) from $(JAR)"

clean:
	rm -f $(WORK)/*.o $(WORK)/archash $(LIB)

distclean:
	rm -rf $(WORK) $(LIB)

# Mindustry tags its releases v<build> and records the Arc commit in
# gradle.properties there. Cached, so this hits the network once.
$(WORK)/archash: | tools
	@mkdir -p $(WORK)
	@b=$$(unzip -p '$(JAR)' version.properties 2>/dev/null | sed -n 's/^build=//p'); \
	 [ -n "$$b" ] || { echo "jar has no build= in version.properties"; exit 1; }; \
	 h=$$(curl -sf --max-time 20 "$(MDT_RAW)/v$$b/gradle.properties" | sed -n 's/^archash=//p'); \
	 [ -n "$$h" ] || { echo "no tag v$$b upstream - self-built jar? then pass ARCHASH=<hash>"; exit 1; }; \
	 echo "Mindustry build $$b needs Arc $$h"; \
	 echo "$$h" > $@

archash: $(WORK)/archash
	@cat $<

ifeq ($(strip $(ARCHASH)),)

# No commit given: resolve it from the jar first, then run the real rules.
patch check: $(WORK)/archash
	@$(MAKE) --no-print-directory $@ ARCHASH="$$(cat $(WORK)/archash)"

else

SRCDIR   := $(WORK)/arc-$(ARCHASH)
JNI      := $(SRCDIR)/backends/backend-sdl/build/jnigen/jni
GEN      := $(SRCDIR)/backends/backend-sdl/build/jnigen/sources
JAVA_INC := $(shell dirname $$(dirname $$(readlink -f $$(command -v javac))))/include

CFLAGS_COMMON := -c -Wall -O2 -fPIC -fmessage-length=0 -DGLEW_STATIC -DGLEW_NO_GLU
INCLUDES       = -I$(JNI) -I$(JNI)/jni-headers -I$(JNI)/jni-headers/linux \
                 -I$(JAVA_INC) -I$(JAVA_INC)/linux -I$(GEN)/glew-2.2.0/include
SDL_CFLAGS    := $(shell sdl2-config --cflags 2>/dev/null)
SDL_LIBS      := $(shell sdl2-config --libs 2>/dev/null)

OBJS := $(WORK)/glew.o $(WORK)/arc_backend_sdl_jni_SDL.o $(WORK)/arc_backend_sdl_jni_SDLGL.o

$(SRCDIR)/.stamp-clone: | tools
	git clone -q $(ARC_REPO) $(SRCDIR)
	git -C $(SRCDIR) checkout -q $(ARCHASH)
	@touch $@

# Generates the C++ sources from the /*JNI ... */ blocks in SDL.java/SDLGL.java
# and downloads GLEW. We stop after jnigen and compile by hand: the gradle path
# would need a local addLinux(..., ARM) patch, and jnigen's compilerPrefix for
# that target (aarch64-linux-gnu-) does not exist on a native arm64 host.
$(SRCDIR)/.stamp-jnigen: $(SRCDIR)/.stamp-clone
	cd $(SRCDIR) && ./gradlew --console=plain :backends:backend-sdl:jnigen
	@touch $@

$(WORK)/glew.o: $(SRCDIR)/.stamp-jnigen
	gcc $(CFLAGS_COMMON) $(INCLUDES) $(SDL_CFLAGS) -o $@ $(GEN)/glew-2.2.0/src/glew.c

$(WORK)/%.o: $(SRCDIR)/.stamp-jnigen
	g++ $(CFLAGS_COMMON) $(INCLUDES) $(SDL_CFLAGS) -o $@ $(JNI)/$*.cpp

$(LIB): $(OBJS)
	g++ -shared -o $@ $(OBJS) $(SDL_LIBS) -Wl,-Bdynamic -lGL
	@file -b $@ | grep -q 'ARM aarch64' || { echo "not an aarch64 object - wrong toolchain?"; rm -f $@; exit 1; }

# Compares the native methods declared in the jar's own Arc classes against the
# symbols the built .so exports. This, not the commit hash, is the real test.
check: $(LIB)
	@rm -rf $(WORK)/abi && mkdir -p $(WORK)/abi
	@unzip -qo '$(JAR)' 'arc/backend/sdl/jni/SDL*.class' -d $(WORK)/abi
	@nm -D --defined-only $(LIB) | awk '{print $$3}' | grep '^Java_' | sort > $(WORK)/abi/syms
	@for c in SDL SDLGL; do \
	    javap -p $(WORK)/abi/arc/backend/sdl/jni/$$c.class \
	    | sed -n 's/.*native [^ ]* \([A-Za-z0-9_]*\)(.*/\1/p' | sed 's/_/_1/g' \
	    | sed "s|^|Java_arc_backend_sdl_jni_$${c}_|"; \
	 done | sort -u > $(WORK)/abi/want
	@miss=0; while read -r n; do \
	    grep -qE "^$$n(__.*)?$$" $(WORK)/abi/syms || { echo "missing symbol: $$n"; miss=1; }; \
	 done < $(WORK)/abi/want; \
	 if [ $$miss = 0 ]; then \
	    echo "$$(wc -l < $(WORK)/abi/want) native methods, all exported by $(LIB)"; \
	 else \
	    echo "$(LIB) (Arc $(ARCHASH)) does not match this jar."; exit 1; \
	 fi

patch: check
	@[ -f '$(JAR).orig' ] || cp -n '$(JAR)' '$(JAR).orig'
	zip -qj '$(JAR)' $(LIB)
	@echo "patched $(JAR) (backup: $(notdir $(JAR)).orig). Undo: make unpatch"

endif
