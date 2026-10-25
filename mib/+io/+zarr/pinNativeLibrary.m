function isPinned = pinNativeLibrary()
% PINNATIVELIBRARY - Keep the native zarr library (zarrMex) loaded until MATLAB exits.
%
% Syntax:
%   .. code-block:: matlab
%
%      isPinned = io.zarr.pinNativeLibrary()
%
% Description:
%   Loads ``zarrMex`` and pins it with ``utils.pinModule`` (a C MEX file, ``mib/+utils/pinModule.c``),
%   so that MATLAB never unmaps it.
%   Called once at MIB startup (``mib3.m``) and by the test fixture
%   ``mibtest.fixtures.MibPathFixture``; later calls return the cached result.
%
%   Why: ``zarrMex`` is a Rust library (zarrs, rayon, tokio) whose worker threads stay alive,
%   parked inside the library, after a call returns. MATLAB unmaps a MEX file at exit and on
%   ``clear mex`` / ``clear functions`` / ``clear zarrMex``; a parked thread that runs again
%   afterwards executes unmapped code and MATLAB crashes with ``0xc0000005`` in
%   ``zarrMex.mexw64_unloaded``. Measured on Windows: a zarr read/write followed by Computer Vision
%   Toolbox feature matching (``utils.stitch.featureShift``) crashed MATLAB at exit in 3 of 3 runs,
%   0 of 5 with the library pinned. The proper fix belongs in zarr-matlab (``mexLock`` in the MEX
%   gateway); this pin is harmless once that is in place.
%
%   Side effect: while MATLAB runs, ``zarrMex.<mexext>`` stays loaded and its file stays locked,
%   so replacing the binary needs a MATLAB restart.
%
%   The library is located with ``which('zarrMex')`` - the path MATLAB itself loads it from, which
%   matters because Windows recognises an already loaded module by its path - and otherwise at
%   ``mib/external/zarr-matlab``, where it is when ``zarr-matlab`` is not on the path yet (tests).
%   Nothing happens when the library or ``utils.pinModule`` is missing for the platform.
%
% Return values:
%   **isPinned** - [logical] ``true`` when zarrMex is loaded and pinned.

persistent pinned
if isempty(pinned)
    pinned = false;
    libraryPath = which('zarrMex');
    if isempty(libraryPath)
        mibFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        libraryPath = fullfile(mibFolder, 'external', 'zarr-matlab', ['zarrMex.' mexext]);
    end
    if isfile(libraryPath)
        try
            pinned = utils.pinModule(libraryPath);
        catch
            % utils.pinModule is not compiled for this platform
        end
    end
end
isPinned = pinned;
end
