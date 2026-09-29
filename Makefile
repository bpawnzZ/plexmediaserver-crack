# Build plexmediaserver_crack.so in an Alpine (musl) container.
#
# The Plex Media Server process is musl, so the library must be built against
# musl — a host glibc build will not load. Requires Docker.

OUT := plexmediaserver_crack.so
IMAGE := plexcrack-build

.PHONY: all clean verify

all: $(OUT)

$(OUT): linux/main.cpp linux/hook.cpp linux/hook.hpp
	docker build -f docker/Dockerfile.build -t $(IMAGE) .
	docker run --rm $(IMAGE) cat /plexmediaserver_crack.so > $(OUT)
	@$(MAKE) --no-print-directory verify

verify:
	@readelf -d $(OUT) | grep -q 'libc.musl-x86_64.so.1' \
	  && echo "ok: $(OUT) is linked against musl" \
	  || { echo "ERROR: $(OUT) is not a musl build"; rm -f $(OUT); exit 1; }

clean:
	rm -f $(OUT)
