function initializeLibraries(obj, initList)
% INITIALIZELIBRARIES - Initialize external libraries and Java paths.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.initializeLibraries()
%      obj.initializeLibraries(initList)
%
% Thin wrapper around ``utils.ensureJavaLibraries`` that supplies the MIB
% installation path and ``preferences.ExternalDirs``. During startup only the
% cheap non-Java libraries are requested (see ``MibController.initialize``);
% Java libraries (Bio-Formats, Fiji, Imaris, ...) are initialized lazily on
% their first use via ``utils.ensureJavaLibraries``.
%
% Input Arguments:
%   - **initList** — *(optional)* cell array of library identifiers to initialize.
%     When empty or missing, all libraries are initialized.
%     Valid identifiers: ``'bm3d'``, ``'omero'``, ``'mij.jar'``, ``'bioformats'``,
%     ``'imageselection'``, ``'fiji'``, ``'poi'``, ``'imaris'``
%
% Output Arguments:
%   (none)
%
% **Example 1** — initialize all libraries:
%
%   .. code-block:: matlab
%
%      obj.initializeLibraries();
%
% **Example 2** — initialize only specific libraries:
%
%   .. code-block:: matlab
%
%      obj.initializeLibraries({'mij.jar', 'bioformats'});
%

arguments (Input)
    obj controllers.MibController
    initList cell = {}  % default empty cell array
end

% empty list keeps the historic behavior: initialize everything
if isempty(initList)
    initList = {'bm3d', 'omero', 'mij.jar', 'bioformats', 'imageselection', 'fiji', 'poi', 'imaris'};
end

utils.ensureJavaLibraries(initList, obj.mibPath, obj.mibModel.preferences.ExternalDirs);

% ------------ add HistThresh thresholding library ------------
if ~isdeployed
    addpath(fullfile(obj.mibPath, 'external', 'HistThresh'));
end

end
