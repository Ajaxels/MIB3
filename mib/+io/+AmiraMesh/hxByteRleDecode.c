/*
 * hxByteRleDecode - decode a stream compressed with Amira's HxByteRLE run-length scheme.
 *
 *   decoded = io.AmiraMesh.hxByteRleDecode(stream, numElements)
 *
 * stream      - column or row vector with the compressed data section of an AmiraMesh block:
 *               uint8 for standard HxByteRLE; uint16 or uint32 for the word-RLE labels files
 *               written by MIB2 for uint16/uint32 models, where control values and data values
 *               are whole words instead of bytes.
 * numElements - number of elements the decoded stream holds (bytes for a uint8 stream).
 * decoded     - column vector of the class of stream with numElements elements, in file order
 *               (x fastest); the caller typecasts and reshapes it.
 *
 * Each packet starts with a control element c:
 *   c & 0x80 set   - (c & 0x7F) literal elements follow;
 *   c & 0x80 clear - the next element is repeated c times.
 * A control value of 0 (as left by some writers as padding) is skipped together with its value.
 *
 * Errors with MIB:hxByteRleDecode:corrupt when a packet would write past numElements, when the
 * stream ends inside a packet, or when it ends before numElements elements were decoded. It
 * never reads or writes out of bounds.
 *
 * Compiled by deployment/mib3_compile_c_files.m.
 */
#include "mex.h"
#include <string.h>

#define DECODE_STREAM(TYPE)                                                                         \
    {                                                                                               \
        const TYPE *input = (const TYPE *)mxGetData(prhs[0]);                                       \
        TYPE *output = (TYPE *)mxGetData(plhs[0]);                                                  \
        size_t inPos = 0, outPos = 0;                                                               \
        while (inPos < streamLength && outPos < numElements) {                                      \
            TYPE control = input[inPos++];                                                          \
            size_t count = (size_t)(control & 0x7F);                                                \
            if (outPos + count > numElements)                                                       \
                mexErrMsgIdAndTxt("MIB:hxByteRleDecode:corrupt",                                    \
                    "The RLE stream decodes to more than the expected %llu elements",               \
                    (unsigned long long)numElements);                                               \
            if (control & 0x80) {                                                                   \
                if (inPos + count > streamLength)                                                   \
                    mexErrMsgIdAndTxt("MIB:hxByteRleDecode:corrupt", "The RLE stream ends inside a literal packet"); \
                memcpy(output + outPos, input + inPos, count * sizeof(TYPE));                       \
                inPos += count;                                                                     \
            } else {                                                                                \
                TYPE value;                                                                         \
                size_t k;                                                                           \
                if (inPos >= streamLength)                                                          \
                    mexErrMsgIdAndTxt("MIB:hxByteRleDecode:corrupt", "The RLE stream ends inside a repeat packet"); \
                value = input[inPos++];                                                             \
                if (sizeof(TYPE) == 1)                                                              \
                    memset(output + outPos, (int)value, count);                                     \
                else                                                                                \
                    for (k = 0; k < count; k++)                                                     \
                        output[outPos + k] = value;                                                 \
            }                                                                                       \
            outPos += count;                                                                        \
        }                                                                                           \
        if (outPos < numElements)                                                                   \
            mexErrMsgIdAndTxt("MIB:hxByteRleDecode:corrupt",                                        \
                "The RLE stream holds %llu of the expected %llu elements",                          \
                (unsigned long long)outPos, (unsigned long long)numElements);                       \
    }

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    size_t streamLength, numElements;
    double requested;
    mxClassID classId;

    if (nrhs != 2 || nlhs > 1)
        mexErrMsgIdAndTxt("MIB:hxByteRleDecode:arguments",
            "Usage: decoded = io.AmiraMesh.hxByteRleDecode(stream, numElements)");
    classId = mxGetClassID(prhs[0]);
    if (mxIsComplex(prhs[0]) || mxIsSparse(prhs[0]) ||
        !(classId == mxUINT8_CLASS || classId == mxUINT16_CLASS || classId == mxUINT32_CLASS))
        mexErrMsgIdAndTxt("MIB:hxByteRleDecode:arguments", "The stream must be a real uint8, uint16 or uint32 vector");
    if (!mxIsNumeric(prhs[1]) || mxGetNumberOfElements(prhs[1]) != 1)
        mexErrMsgIdAndTxt("MIB:hxByteRleDecode:arguments", "numElements must be a numeric scalar");
    requested = mxGetScalar(prhs[1]);
    if (requested < 0 || requested != (double)(size_t)requested)
        mexErrMsgIdAndTxt("MIB:hxByteRleDecode:arguments", "numElements must be a non-negative integer");

    streamLength = mxGetNumberOfElements(prhs[0]);
    numElements = (size_t)requested;
    /* every element is written below or the call errors, so the buffer needs no zero fill */
    plhs[0] = mxCreateUninitNumericMatrix(numElements, 1, classId, mxREAL);

    switch (classId) {
        case mxUINT8_CLASS:
            DECODE_STREAM(unsigned char)
            break;
        case mxUINT16_CLASS:
            DECODE_STREAM(unsigned short)
            break;
        default:
            DECODE_STREAM(unsigned int)
            break;
    }
}
