function [stitchOptions, values] = stitchInstancesSettingsDlg(parentFigure, note, defaults, dlgOptions)
% STITCHINSTANCESSETTINGSDLG - Ask for the 2D-to-3D instance stitching settings.
%
% Syntax:
%   .. code-block:: matlab
%
%       [stitchOptions, values] = utils.dlgs.stitchInstancesSettingsDlg(parentFigure, note, defaults, dlgOptions)
%
% The single definition of the settings dialog for
% :func:`utils.instances.stitch2Dto3D`, shared by its two entry points:
% :func:`models.MibModel.stitchModelInstances` (stitches the active labels
% layer) and :func:`controllers.MibDeep.mergeInstancesTo3D` (stitches predicted
% ``*.model`` files from disk). Keeping one copy means a new stitching parameter
% is added in one place instead of two hand-synchronised prompt lists - the two
% dialogs previously had to be renumbered in lockstep, with nothing to catch a
% mismatched ``answer{n}`` index.
%
% On acceptance the chosen settings are echoed to the console as one line, built
% by walking the returned options struct, so a trial can be reproduced from the
% log without a second list to keep in step.
%
% The dialog itself is stateless - a caller that wants the widgets to reopen on
% the last-used values stores the returned ``values`` struct and hands it back as
% ``defaults`` next time. A seeded numeric outside a widget's range is clamped
% rather than rejected, so a stale entry cannot break the dialog, and a
% ``defaults`` field the dialog does not know is ignored, because the seeding
% walks the dialog's own field list rather than what it was given.
%
% Both callers persist under **one shared key**,
% ``MibModel.sessionSettings.stitchInstances2Dto3D``, so a threshold trialled at
% one entry point is offered at the other. They write into it field by field
% instead of replacing it, because the anisotropy answer is the one value that
% cannot be shared - see ``anisotropyMode`` below. It lives under
% ``UseAnisotropy`` (the checkbox) and ``Anisotropy`` (the ratio), and each
% caller touches only its own.
%
% The callers differ only in how the Z anisotropy is obtained, which
% ``dlgOptions.anisotropyMode`` selects:
%
%   - ``'checkbox'`` - a yes/no toggle; the caller derives the ratio from its
%     dataset's ``pixSize.z / pixSize.x``. ``anisotropyZ`` is **not** set in
%     ``stitchOptions``; read ``values.Anisotropy`` (logical) and set it.
%   - ``'ratio'`` - a numeric spinner, for input that carries no pixel size
%     (raw prediction images). ``anisotropyZ`` is set in ``stitchOptions``
%     whenever the entered ratio exceeds 1.
%
% Input Arguments:
%   - **parentFigure** - handle of the parent figure for the modal dialog
%   - **note** - char, the bold header text shown above the settings
%   - **defaults** - *(optional)* structure seeding the widgets; every field is
%     optional and falls back to the value below. Field names match those of
%     ``values``:
%
%     - ``.Method`` - ``'graph'`` (default) or ``'hungarian'``
%     - ``.SplitDisconnected2D`` - logical [*default* ``true``]
%     - ``.IoUThreshold`` - numeric 0-1 [*default* ``0.25``]
%     - ``.IoAThreshold`` - logical, enables containment merging [*default* ``true``]
%     - ``.MinOverlapPixels`` - numeric [*default* ``5``]
%     - ``.AbsOverlapPixels`` - numeric, ``0`` = off [*default* ``0``]
%     - ``.ZLookback`` - numeric [*default* ``1``]
%     - ``.MinObjectVoxels`` - numeric, ``0`` = keep all [*default* ``0``]
%     - ``.MinObjectSlices`` - numeric, ``0`` = keep all [*default* ``0``]
%     - ``.AbsorbFragmentVoxels`` - numeric, ``0`` = off [*default* ``5``]
%     - ``.Anisotropy`` - logical in ``'checkbox'`` mode [*default* ``false``],
%       numeric ratio in ``'ratio'`` mode [*default* ``1``]
%     - ``.MaxCentroidShift`` - numeric, ``0`` = off [*default* ``0``]
%     - ``.CentroidLinkRadius`` - numeric, ``0`` = off [*default* ``0``]
%
%   - **dlgOptions** - *(optional)* structure:
%
%     - ``.anisotropyMode`` - ``'checkbox'`` (default) or ``'ratio'``
%     - ``.dlgTitle`` - dialog window title [*default* ``'Stitch 2D instances to 3D'``]
%     - ``.mibPath`` - MIB installation path. Supplies the dialog icon and the
%       Help button, which opens the *Stitch 2D instances to 3D* documentation
%       page - the local copy under ``docs/html`` when the documentation was
%       built, the page on mib.helsinki.fi otherwise. Without it the dialog
%       still works, but shows no Help button
%
% Output Arguments:
%   - **stitchOptions** - structure ready for :func:`utils.instances.stitch2Dto3D`;
%     ``[]`` when the user cancelled
%   - **values** - structure of the raw widget values under the ``defaults``
%     field names, so a caller can write them back into its own ``BatchOpt``;
%     ``[]`` when the user cancelled
%
% **Example** - the MibDeep call site, which supplies its own anisotropy ratio:
%
%   .. code-block:: matlab
%
%      dlgOptions.anisotropyMode = 'ratio';
%      dlgOptions.dlgTitle = 'Merge 2D instances to 3D';
%      dlgOptions.mibPath = obj.mibModel.mibPath;
%      [stitchOptions, values] = utils.dlgs.stitchInstancesSettingsDlg( ...
%          obj.view.gui, note, struct(), dlgOptions);
%      if isempty(stitchOptions); return; end   % cancelled

% Updates
%

if nargin < 3 || isempty(defaults); defaults = struct(); end
if nargin < 4 || isempty(dlgOptions); dlgOptions = struct(); end
if ~isfield(dlgOptions, 'anisotropyMode'); dlgOptions.anisotropyMode = 'checkbox'; end
if ~isfield(dlgOptions, 'dlgTitle');       dlgOptions.dlgTitle = 'Stitch 2D instances to 3D'; end

ratioMode = strcmpi(dlgOptions.anisotropyMode, 'ratio');

% built-in defaults, overridden by whatever the caller seeded
def = struct('Method', 'graph', 'SplitDisconnected2D', true, 'IoUThreshold', 0.25, ...
    'IoAThreshold', true, 'MinOverlapPixels', 5, 'AbsOverlapPixels', 0, 'ZLookback', 1, ...
    'MinObjectVoxels', 0, 'MinObjectSlices', 0, 'AbsorbFragmentVoxels', 5, ...
    'MaxCentroidShift', 0, 'CentroidLinkRadius', 0);
if ratioMode; def.Anisotropy = 1; else; def.Anisotropy = false; end

% Spinner limits, defined once and used both for the widgets below and to clamp
% the seeded values. A caller restoring settings saved in an earlier session
% cannot then hand a spinner a value outside its own range.
limits = struct('IoUThreshold', [0, 1], 'MinOverlapPixels', [0, 1e6], ...
    'AbsOverlapPixels', [0, 1e9], 'ZLookback', [1, 100], 'MinObjectVoxels', [0, 1e9], ...
    'MinObjectSlices', [0, 1e6], 'AbsorbFragmentVoxels', [0, 1e6], ...
    'MaxCentroidShift', [0, 1e6], 'CentroidLinkRadius', [0, 1e6]);
if ratioMode; limits.Anisotropy = [1, 1000]; end

fieldList = fieldnames(def);
for k = 1:numel(fieldList)
    name = fieldList{k};
    if ~isfield(defaults, name) || isempty(defaults.(name)); continue; end
    seeded = defaults.(name);
    if isfield(limits, name)
        if ~isnumeric(seeded) && ~islogical(seeded) || ~isscalar(seeded); continue; end
        range = limits.(name);
        seeded = min(max(double(seeded), range(1)), range(2));
    end
    def.(name) = seeded;
end

%% Widget definitions
methodItems = {'graph', 'hungarian'};
methodDefault = find(strcmp(methodItems, def.Method));
if isempty(methodDefault); methodDefault = 1; end

% Prompts are one reminder line each; the Help button opens the page that
% explains and illustrates every setting, so the dialog does not have to.
if ratioMode
    anisotropyPrompt = sprintf(['Z anisotropy ratio (voxel Z-size / XY-size):\n' ...
        '  lowers the IoU threshold for thick sections; 1 = isotropic (off)']);
    anisotropyWidget = struct('Spinner', true, 'Value', def.Anisotropy, 'Limits', limits.Anisotropy, ...
        'Step', 0.5, 'Round', false);
else
    anisotropyPrompt = sprintf(['Anisotropic Z (use pixel size):\n' ...
        '  lower the IoU threshold by pixSize.z/pixSize.x for thick sections']);
    anisotropyWidget = logical(def.Anisotropy);
end

prompt = {...
    sprintf('Method:\n  "graph" links every overlapping pair, "hungarian" matches strictly 1-to-1'), ...
    sprintf('Split disconnected 2D objects:\n  treat each separate blob of a per-slice index as its own object'), ...
    sprintf('IoU threshold (0-1):\n  join when overlap/union exceeds this; higher = stricter'), ...
    sprintf('Merge split objects (IoA):\n  also join when a smaller object lies mostly inside its neighbour'), ...
    sprintf('Min overlap (pixels):\n  never link on fewer overlapping pixels than this'), ...
    sprintf('Absolute overlap to link (pixels):\n  always link on this many shared pixels, whatever the IoU/IoA; 0 = off'), ...
    sprintf('Z lookback (slices):\n  1 = adjacent slices only, higher bridges an object that briefly vanishes\n\nCLEANUP'), ...
    sprintf('Min object size (voxels):\n  delete 3D objects smaller than this; 0 = keep all'), ...
    sprintf('Min object depth (slices):\n  delete 3D objects seen on this many slices or fewer; 0 = keep all'), ...
    sprintf('Absorb fragments (voxels):\n  give objects this small to the object around them; 0 = off\n\nTHICK SECTIONS AND GAPS'), ...
    anisotropyPrompt, ...
    sprintf('Max centroid shift (pixels):\n  reject a link when the centroids are farther apart than this; 0 = off'), ...
    sprintf('Centroid link radius (pixels):\n  bridge a gap to the nearest object within this distance; 0 = off')};

defAns = {[methodItems, {methodDefault}], ...
          logical(def.SplitDisconnected2D), ...
          struct('Spinner', true, 'Value', def.IoUThreshold,       'Limits', limits.IoUThreshold,       'Step', 0.05, 'Round', false), ...
          logical(def.IoAThreshold), ...
          struct('Spinner', true, 'Value', def.MinOverlapPixels,   'Limits', limits.MinOverlapPixels,   'Step', 1,    'Round', true), ...
          struct('Spinner', true, 'Value', def.AbsOverlapPixels,   'Limits', limits.AbsOverlapPixels,   'Step', 10,   'Round', true), ...
          struct('Spinner', true, 'Value', def.ZLookback,          'Limits', limits.ZLookback,          'Step', 1,    'Round', true), ...
          struct('Spinner', true, 'Value', def.MinObjectVoxels,    'Limits', limits.MinObjectVoxels,    'Step', 1,    'Round', true), ...
          struct('Spinner', true, 'Value', def.MinObjectSlices,    'Limits', limits.MinObjectSlices,    'Step', 1,    'Round', true), ...
          struct('Spinner', true, 'Value', def.AbsorbFragmentVoxels, 'Limits', limits.AbsorbFragmentVoxels, 'Step', 1, 'Round', true), ...
          anisotropyWidget, ...
          struct('Spinner', true, 'Value', def.MaxCentroidShift,   'Limits', limits.MaxCentroidShift,   'Step', 1,    'Round', true), ...
          struct('Spinner', true, 'Value', def.CentroidLinkRadius, 'Limits', limits.CentroidLinkRadius, 'Step', 1,    'Round', true)};

dlgParams.WindowWidth = 720;
dlgParams.WindowHeight = 665;
dlgParams.HeaderLines = 2;
dlgParams.LabelPosition = 'left';
if isfield(dlgOptions, 'mibPath')
    dlgParams.mibPath = dlgOptions.mibPath;
    % a function handle rather than an address, so the local page is preferred
    % over the online one when the documentation was built
    helpPage = fullfile(fileparts(dlgOptions.mibPath), 'docs', 'html', ...
        'user-interface', 'ribbon', 'model', 'instance-stitching.html');
    dlgParams.HelpUrl = @() utils.openHelpPage(helpPage, ...
        'http://mib.helsinki.fi/help/main3/user-interface/ribbon/model/instance-stitching.html');
end

answer = utils.dlgs.inputUniversalDlg(parentFigure, note, prompt, defAns, dlgOptions.dlgTitle, dlgParams);
if isempty(answer); stitchOptions = []; values = []; return; end

%% Raw widget values, under the same names the caller seeded
values = struct();
values.Method              = answer{1};
values.SplitDisconnected2D = answer{2};
values.IoUThreshold        = answer{3};
values.IoAThreshold        = answer{4};
values.MinOverlapPixels    = answer{5};
values.AbsOverlapPixels    = answer{6};
values.ZLookback           = answer{7};
values.MinObjectVoxels     = answer{8};
values.MinObjectSlices       = answer{9};
values.AbsorbFragmentVoxels  = answer{10};
values.Anisotropy            = answer{11};
values.MaxCentroidShift      = answer{12};
values.CentroidLinkRadius    = answer{13};

%% Options for utils.instances.stitch2Dto3D
% The IoA checkbox maps to a 0.5 containment threshold when enabled, Inf (never
% links) when disabled.
ioaEnabledThreshold = 0.5;
stitchOptions = struct();
stitchOptions.method = values.Method;
stitchOptions.splitDisconnected2D = logical(values.SplitDisconnected2D);
stitchOptions.iouThreshold = values.IoUThreshold;
if values.IoAThreshold
    stitchOptions.ioaThreshold = ioaEnabledThreshold;
else
    stitchOptions.ioaThreshold = inf;
end
stitchOptions.minOverlapPixels = values.MinOverlapPixels;
stitchOptions.absOverlapPixels = values.AbsOverlapPixels;
stitchOptions.zLookback = values.ZLookback;
stitchOptions.minObjectVoxels = values.MinObjectVoxels;
stitchOptions.minObjectSlices = values.MinObjectSlices;
stitchOptions.absorbFragmentVoxels = values.AbsorbFragmentVoxels;
% Ratio mode owns the anisotropy value; checkbox mode leaves anisotropyZ unset
% so the caller can derive it from its dataset pixel size.
if ratioMode && values.Anisotropy > 1
    stitchOptions.anisotropyZ = values.Anisotropy;
end
% 0 in the UI means disabled for both gates (Inf inside the utility).
if values.MaxCentroidShift > 0
    stitchOptions.maxCentroidShift = values.MaxCentroidShift;
end
if values.CentroidLinkRadius > 0
    stitchOptions.centroidLinkRadius = values.CentroidLinkRadius;
end

%% Echo the accepted settings, so a trial can be reproduced from the console log
% Built by walking stitchOptions itself rather than from a hand-written list, so
% a parameter added above appears here without a second edit. Fields left unset
% (a disabled gate) are simply absent, which is the honest report - they are not
% passed to the utility either.
if ~isempty(stitchOptions)
    optionNames = fieldnames(stitchOptions);
    parts = cell(1, numel(optionNames));
    for k = 1:numel(optionNames)
        optionValue = stitchOptions.(optionNames{k});
        if ischar(optionValue)
            parts{k} = sprintf('%s=%s', optionNames{k}, optionValue);
        elseif islogical(optionValue)
            parts{k} = sprintf('%s=%d', optionNames{k}, optionValue);
        else
            parts{k} = sprintf('%s=%g', optionNames{k}, optionValue);
        end
    end
    if ~ratioMode
        % checkbox mode: anisotropyZ is not in stitchOptions, the caller derives it
        parts{end+1} = sprintf('useAnisotropy=%d', values.Anisotropy);
    end
    fprintf('%s: %s\n', dlgOptions.dlgTitle, strjoin(parts, ', '));
end
end
