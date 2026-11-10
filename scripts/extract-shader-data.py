#!/usr/bin/env python3
"""Takes from a Forza Horizon 2 (Xbox 360) disc image only the files the
native renderer's shader library is made from: media/shaders/**/*.fxobj and
the track archives media/tracks/**/*.zip (tools/xenos/extrair_*.py read them).
Uses FH2 Recompiled's own disc reader (tools/fase1_extraer.py), so the paths
come out as a full extraction would give them.

The track archives are up to 3 GB each, and only their .fxobj entries are
read: they are written as sparse files holding just the central directory
and those entries' data at their own offsets, the rest left as holes, so they
take a few MB on disk and read the same to extrair_fxobj_pistas.py.

    scripts/extract-shader-data.py FH2_RECOMPILED ISO OUT
"""
import io
import os
import sys
import zipfile


class Window(io.RawIOBase):
    """A read-only view of SIZE bytes at OFFSET in an open file."""

    def __init__(self, fh, offset, size):
        self.fh, self.offset, self.size, self.pos = fh, offset, size, 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def seek(self, pos, whence=0):
        self.pos = pos if whence == 0 else self.pos + pos if whence == 1 else self.size + pos
        return self.pos

    def tell(self):
        return self.pos

    def readinto(self, buf):
        n = max(0, min(len(buf), self.size - self.pos))
        self.fh.seek(self.offset + self.pos)
        data = self.fh.read(n)
        buf[:len(data)] = data
        self.pos += len(data)
        return len(data)


def copy_range(src, dst, start, length):
    src.seek(start)
    dst.seek(start)
    while length > 0:
        chunk = src.read(min(length, 1 << 20))
        if not chunk:
            raise SystemExit("error: the disc image ends inside a track archive")
        dst.write(chunk)
        length -= len(chunk)


def extract_track_zip(fh, offset, size, dest):
    """The archive's central directory and its .fxobj entries, sparse."""
    view = Window(fh, offset, size)
    z = zipfile.ZipFile(io.BufferedReader(view, 1 << 16))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as out:
        out.truncate(size)
        copy_range(view, out, z.start_dir, size - z.start_dir)
        n = 0
        for i in z.infolist():
            if i.filename.lower().endswith(".fxobj"):
                # FH2's archives keep an entry's data right at header_offset;
                # an ordinary local header (30 bytes, name, extra) is covered too.
                start = i.header_offset
                copy_range(view, out, start, min(size - start, 30 + 65535 * 2 + i.compress_size))
                n += 1
    return n


def wanted(path):
    p = path.lower()
    return ((p.startswith("media/shaders/") and p.endswith(".fxobj")) or
            (p.startswith("media/tracks/") and p.endswith(".zip")))


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    fh2, iso, out = sys.argv[1:]
    sys.path.insert(0, os.path.join(fh2, "tools"))
    import fase1_extraer as disc

    with open(iso, "rb") as fh:
        base, _ = disc.detectar_base(fh)
        sector, size = disc.leer_descriptor(fh, base)
        files = [(path, e) for path, e in disc.recorrer(fh, base, sector, size)
                 if not e["dir"] and wanted(path)]
        if not any(p.lower().startswith("media/shaders/") for p, _ in files):
            sys.exit("error: no media/shaders/*.fxobj on the disc: is this Forza Horizon 2 for Xbox 360?")
        shaders = 0
        for path, e in files:
            dest = os.path.join(out, *path.split("/"))
            if path.lower().endswith(".zip"):
                n = extract_track_zip(fh, base + e["sector"] * disc.SECTOR, e["tam"], dest)
                print("  %s: %d shader files" % (path, n))
            else:
                disc.extraer(fh, base, e, dest)
                shaders += 1
        print("  media/shaders: %d files" % shaders)


if __name__ == "__main__":
    main()
