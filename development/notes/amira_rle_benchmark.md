# AmiraMesh HxByteRLE: encoder design and measurements

Measured 2026-11-01, R2026a, Windows workstation, MinGW64 `-O2`, files written to the local
temp folder (OS write cache absorbs the writes, so these are CPU-bound numbers). Every
measurement ran in a separate `matlab -batch` process.

Code: `mib/+io/+AmiraMesh/hxByteRleEncode.c`, `hxByteRleDecode.c`; used by
`bitmap2amiraMesh.m` (image), `bitmap2amiraLabels.m` (labels/mask), read by
`amiraMesh2bitmap.m` and `amiraLabels2bitmap.m`. Tests: `tests/io/AmiraMeshRleTest.m`.

## End-to-end, through `io.SaverFactory` savers (2048 x 2048)

| Data | Plain binary save | RLE save | RLE file | RLE load |
|------|------------------|----------|----------|----------|
| uint8 EM-like noise, 200 slices (839 MB) | 2.23 s | 2.27 s | 845 MB (+0.8%) | 3.92 s (plain 3.51 s) |
| uint16 EM-like noise, 100 slices (839 MB) | 1.49 s | 1.69 s | 845 MB | 4.50 s (plain 4.13 s) |
| uint8 labels, blocky, 200 slices (839 MB) | 1.10 s | 1.73 s | 44.7 MB | 0.50 s (plain 0.48 s) |

The MIB2 MATLAB-loop encoder ran at about 27 MB/s on blocky labels (~30 s for the volume
above).

The labels row is the only one clearly above plain binary: the plain labels writer does one
multithreaded whole-volume `permute`, the RLE writer one `.'` per slice. On a real disk or a
network share, writing 45 MB instead of 839 MB more than pays this back.

## Encoder speed alone (4096 x 4096 uint8 slices)

| Variant | 10 slices |
|---------|-----------|
| slice extract only | 0.10 s |
| extract + MATLAB `.'` | 0.18 s |
| extract + `.'` + encode, EM noise (byte-wise literal scan) | 0.32 s |
| same, 8-byte word scan for literals and runs | 0.26 s |
| same, labels | 0.20 s |
| plain `fwrite` of the transposed slice | 0.25 s |

So the encoder runs at ~2 GB/s on noise and ~8 GB/s on labels. The rest is MATLAB moving the
data.

## Alternatives tried and rejected

- **Transpose inside the MEX file.** A direct scalar transpose writing to the scratch buffer
  took 1.29 s for 10 slices: 64 destination rows 4096 bytes apart map to one cache set.
  Going through a local 64 x 64 tile buffer brought it to 0.48-0.58 s. That is still slower
  than MATLAB's vectorised `.'` plus encoding (0.33 s). The MEX encodes its input in memory
  order, and callers pass `slice.'`. A SIMD transpose (SSE2/NEON) could beat `.'` but would
  need two code paths.
- **`-O3`**: 0.48-0.52 s vs 0.58 s for the tiled-transpose build, within noise for the final
  encoder. The default `-O2` is kept.
- **Chunks of slices with one `permute`** (labels, 2048 x 2048 x 200): per slice 1.16 s,
  4 slices 1.45 s, 16 slices 1.08 s, 64 slices 1.00 s. Not worth the extra memory and code.
- **Buffering the whole stream to know its size first.** Instead, the Lattice line gets a
  21-character placeholder (`<size>)` + trailing spaces) that is overwritten with `fseek` once
  the block is written. Memory stays at one slice.

## Packet rules and the output bound

The first encoder version ended a literal packet for every run of 2. A 1-byte literal plus a
2-byte run costs 4 bytes for 3, which overran the `n + n/127` buffer and crashed MATLAB. Now
a run of 2 joins an open literal packet, which restores the bound (proof in the C header). The
encoder also checks capacity once per run and grows the buffer, so a wrong bound can't crash.

## MIB2 RLE files

The MIB2 writer (`bitmap2amiraLabels`, `binaryRLE`) is broken:
- uint8: on a 20 x 23 x 3 random labels volume the stream differs from the data at element 6
  and decodes to 1497 instead of 1380 elements;
- uint16: on 20 x 23 x 3 data it did not finish within 600 s (infinite loop).
It wrote uint16/uint32 packets as whole words and counted words in the header.
`amiraLabels2bitmap` still reads that layout: it detects it by the length of the data
section. Streams that decode to the wrong number of elements are rejected
(`MIB:hxByteRleDecode:corrupt`) rather than loaded as garbage.

## Not verified

Not tested in Amira/Avizo:
- whether Amira's parser accepts the padded size field;
- whether it reads byte-level RLE for `ushort` data.
