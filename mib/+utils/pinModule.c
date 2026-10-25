/*
 * pinModule - load a shared library and keep it mapped until the process exits.
 *
 *   isPinned = utils.pinModule(libraryPath)
 *
 * libraryPath - full path of the library (a MEX file, for example); it is loaded when it is not
 *               loaded yet.
 * isPinned    - logical true when the library is loaded and pinned.
 *
 * Why: a MEX file that leaves worker threads alive after a call (thread pools of Rust's rayon or
 * tokio, as in zarrMex) crashes MATLAB when MATLAB unmaps the library while those threads still
 * exist - at exit, and after "clear mex". A pinned library is never unmapped: FreeLibrary/dlclose
 * become no-ops for it, MATLAB's later load of the same path returns the same module, and the
 * threads end with the process. See io.zarr.pinNativeLibrary.
 *
 * Windows: LoadLibraryExW + GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN).
 * Linux/macOS: dlopen with RTLD_NODELETE.
 *
 * Compiled by deployment/mib3_compile_c_files.m.
 */
#include "mex.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    char *libraryPath;
    int isPinned = 0;

    if (nrhs != 1 || !mxIsChar(prhs[0]))
        mexErrMsgIdAndTxt("MIB:pinModule:arguments", "Usage: isPinned = utils.pinModule(libraryPath)");
    libraryPath = mxArrayToUTF8String(prhs[0]);
    if (libraryPath == NULL)
        mexErrMsgIdAndTxt("MIB:pinModule:arguments", "The library path could not be read");

#ifdef _WIN32
    {
        int wideLength = MultiByteToWideChar(CP_UTF8, 0, libraryPath, -1, NULL, 0);
        wchar_t *widePath = (wchar_t *)mxMalloc(wideLength * sizeof(wchar_t));
        HMODULE library;
        HMODULE pinned = NULL;
        MultiByteToWideChar(CP_UTF8, 0, libraryPath, -1, widePath, wideLength);
        /* the same flag MATLAB loads MEX files with, so dependencies resolve from the library folder */
        library = LoadLibraryExW(widePath, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
        if (library != NULL)
            isPinned = GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                                          (LPCWSTR)library, &pinned) != 0;
        mxFree(widePath);
    }
#else
    isPinned = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL | RTLD_NODELETE) != NULL;
#endif

    mxFree(libraryPath);
    plhs[0] = mxCreateLogicalScalar(isPinned != 0);
}
