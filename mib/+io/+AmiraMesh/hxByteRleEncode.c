/*
 * hxByteRleEncode - encode data with Amira's HxByteRLE run-length scheme.
 *
 *   encoded = io.AmiraMesh.hxByteRleEncode(data)
 *
 * data    - array of any real integer class (uint8, int8, uint16, int16, uint32, int32, uint64,
 *           int64) and any shape. Its bytes are encoded in memory order, so the caller passes
 *           the data already in Amira order (x fastest): a MIB [H, W] slice goes in as slice.'
 * encoded - uint8 column vector with the HxByteRLE stream. Multi-byte elements are encoded as
 *           their bytes in host order, which is little-endian on every platform MATLAB supports.
 *
 * HxByteRLE is a stream of packets, each starting with a control byte c:
 *   c & 0x80 set   - (c & 0x7F) literal bytes follow (1..127);
 *   c & 0x80 clear - the next byte is repeated c times (1..127).
 * A run of 3 or more equal bytes becomes repeat packets (split at 127). Everything between such
 * runs is copied into literal packets in blocks. A run of 2 becomes a repeat packet only when no
 * literal packet is open, otherwise it joins that packet.
 *
 * Output size bound: a literal packet of k bytes costs k + 1, and a short one is only closed by
 * a following run of 3 or more, which saves at least one byte (L bytes cost at most L - 1). A
 * run of 2 outside a literal packet costs 2. So the stream never exceeds n + n/127 + 1 bytes
 * for n input bytes, which is the size of the output buffer. Ending a literal packet for every
 * run of 2 would break this bound (1 literal + 2 run = 4 bytes for 3). The buffer is still
 * checked once per stretch and grown if needed, so a wrong bound costs a reallocation, not a
 * crash. The buffer is shrunk to the encoded size before it is returned.
 *
 * Every call ends with its last literal packet closed, so the streams of consecutive calls can
 * be written one after another into the same data section; io.AmiraMesh.bitmap2amiraMesh and
 * io.AmiraMesh.bitmap2amiraLabels encode one slice per call this way.
 *
 * The transpose to Amira order is left to MATLAB on purpose: its .' is vectorised, and
 * ".' + this encoder" measured faster than a tiled scalar transpose inside the MEX file
 * (4096 x 4096 uint8 slices; see development/notes/amira_rle_benchmark.md).
 *
 * Compiled by deployment/mib3_compile_c_files.m.
 */
#include "mex.h"
#include <string.h>

#define MAX_PACKET 127

typedef struct {
    unsigned char *out;     /* output buffer */
    size_t outPos;          /* next write position in out */
    size_t capacity;        /* allocated size of out */
    size_t literalHeader;   /* position of the control byte of the open literal packet */
    size_t literalLength;   /* bytes in the open literal packet, 0 = none open */
} Encoder;

/* A stretch of length bytes never needs more than 2 * length + 2 output bytes. */
static void reserve(Encoder *encoder, size_t length)
{
    size_t needed = encoder->outPos + 2 * length + 2;
    if (needed > encoder->capacity) {
        size_t newCapacity = encoder->capacity + encoder->capacity / 2;
        if (newCapacity < needed)
            newCapacity = needed;
        encoder->out = (unsigned char *)mxRealloc(encoder->out, newCapacity);
        encoder->capacity = newCapacity;
    }
}

static void closeLiteral(Encoder *encoder)
{
    if (encoder->literalLength > 0) {
        encoder->out[encoder->literalHeader] = (unsigned char)(0x80 | encoder->literalLength);
        encoder->literalLength = 0;
    }
}

/* Both scans below test 8 bytes per step with word operations and only fall back to single
   bytes inside the word where the answer changes; this roughly halved the time of a noisy
   (literal-heavy) slice. Unaligned loads go through memcpy, which compilers turn into a plain
   load. */
#define ONES  0x0101010101010101ULL
#define HIGHS 0x8080808080808080ULL
#define HAS_ZERO_BYTE(word) (((word) - ONES) & ~(word) & HIGHS)

static unsigned long long load64(const unsigned char *pointer)
{
    unsigned long long word;
    memcpy(&word, pointer, sizeof(word));
    return word;
}

/* end of the run of value that starts at position */
static size_t findRunEnd(const unsigned char *bytes, size_t position, size_t numBytes)
{
    unsigned char value = bytes[position];
    unsigned long long pattern = ONES * value;
    size_t runEnd = position + 1;
    while (runEnd + 8 <= numBytes && load64(bytes + runEnd) == pattern)
        runEnd += 8;
    while (runEnd < numBytes && bytes[runEnd] == value)
        runEnd++;
    return runEnd;
}

/* first position >= start where 3 equal bytes begin, or numBytes when there is none */
static size_t findTriple(const unsigned char *bytes, size_t start, size_t numBytes)
{
    size_t position = start;
    while (position + 10 <= numBytes) {
        /* zero byte k in differences <=> bytes[position + k .. position + k + 2] are equal */
        unsigned long long differences = (load64(bytes + position) ^ load64(bytes + position + 1)) |
                                         (load64(bytes + position + 1) ^ load64(bytes + position + 2));
        if (HAS_ZERO_BYTE(differences))
            break;
        position += 8;
    }
    for (; position + 2 < numBytes; position++)
        if (bytes[position] == bytes[position + 1] && bytes[position] == bytes[position + 2])
            return position;
    return numBytes;
}

static void encodeBytes(Encoder *encoder, const unsigned char *bytes, size_t numBytes)
{
    size_t position = 0;
    while (position < numBytes) {
        unsigned char value = bytes[position];
        size_t runEnd = findRunEnd(bytes, position, numBytes);
        size_t runLength = runEnd - position;

        if (runLength >= 3 || (runLength == 2 && encoder->literalLength == 0)) {
            reserve(encoder, runLength);
            closeLiteral(encoder);
            while (runLength > 0) {
                size_t chunk = runLength < MAX_PACKET ? runLength : MAX_PACKET;
                encoder->out[encoder->outPos++] = (unsigned char)chunk;
                encoder->out[encoder->outPos++] = value;
                runLength -= chunk;
            }
            position = runEnd;
        } else {
            /* literal stretch: everything up to the next run of 3 or more equal bytes */
            size_t stretchEnd = findTriple(bytes, position + 1, numBytes);
            size_t remaining = stretchEnd - position;
            const unsigned char *source = bytes + position;
            reserve(encoder, remaining);
            while (remaining > 0) {
                size_t chunk;
                if (encoder->literalLength == 0)
                    encoder->literalHeader = encoder->outPos++;
                chunk = MAX_PACKET - encoder->literalLength;
                if (chunk > remaining)
                    chunk = remaining;
                memcpy(encoder->out + encoder->outPos, source, chunk);
                encoder->outPos += chunk;
                encoder->literalLength += chunk;
                source += chunk;
                remaining -= chunk;
                if (encoder->literalLength == MAX_PACKET)
                    closeLiteral(encoder);
            }
            position = stretchEnd;
        }
    }
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    const mxArray *data;
    size_t numBytes, capacity;
    Encoder encoder;

    if (nrhs != 1 || nlhs > 1)
        mexErrMsgIdAndTxt("MIB:hxByteRleEncode:arguments", "Usage: encoded = io.AmiraMesh.hxByteRleEncode(data)");
    data = prhs[0];
    if (mxIsComplex(data) || mxIsSparse(data) ||
        !(mxIsUint8(data) || mxIsInt8(data) || mxIsUint16(data) || mxIsInt16(data) ||
          mxIsUint32(data) || mxIsInt32(data) || mxIsUint64(data) || mxIsInt64(data)))
        mexErrMsgIdAndTxt("MIB:hxByteRleEncode:arguments", "The data must be a real, full integer array");

    numBytes = mxGetNumberOfElements(data) * mxGetElementSize(data);
    capacity = numBytes + numBytes / MAX_PACKET + 16;
    encoder.out = (unsigned char *)mxMalloc(capacity);
    encoder.outPos = 0;
    encoder.capacity = capacity;
    encoder.literalHeader = 0;
    encoder.literalLength = 0;

    encodeBytes(&encoder, (const unsigned char *)mxGetData(data), numBytes);
    closeLiteral(&encoder);

    plhs[0] = mxCreateNumericMatrix(0, 1, mxUINT8_CLASS, mxREAL);
    if (encoder.outPos > 0) {
        encoder.out = (unsigned char *)mxRealloc(encoder.out, encoder.outPos);
        mxSetData(plhs[0], encoder.out);
        mxSetM(plhs[0], encoder.outPos);
    } else {
        mxFree(encoder.out);
    }
}
