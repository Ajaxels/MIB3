function tweaks = generateTweaks()
% GENERATETWEAKS - Describe the settings listed in Preferences -> Fine-tuning.
%
% Syntax:
%   .. code-block:: matlab
%
%      tweaks = utils.defaults.generateTweaks()
%
% Fine-tuning collects small settings that change *how much* an existing action
% does (the zoom step of the Q/W keys, the slice step of the arrow keys, ...) and that
% most users never touch, so they do not deserve a widget of their own. The
% Preferences dialog shows them in one table and edits the selected row with a single
% widget chosen by ``Type``; nothing else in the dialog has to change when a setting
% is added here.
%
% This function holds only the *description* of the settings. Their default values
% live in :func:`utils.defaults.generatePreferences` like every other preference, so
% that ``initializePreferences`` restores a missing or damaged value from there and
% ``saveOverridePreferences`` writes a changed one into the override JSON (with
% ``Description`` as its ``_comment``).
%
% **Adding a setting:**
%
%   1. give it a default in ``generatePreferences``, under ``Prefs.Tweaks.<Group>.<Name>``
%   2. describe it here with one ``describeTweak`` line
%   3. read it at the place of use as ``obj.mibModel.preferences.Tweaks.<Group>.<Name>``
%
% A setting does not have to be under ``Tweaks``: ``Path`` may name any existing
% preference that has no widget elsewhere in the dialog (``ImageArithmetic.NoStoredActions``),
% which exposes it without moving it and breaking old ``mib3.mat`` files.
%
% Output Arguments:
%   - **tweaks** - [struct array] one element per setting, in the order of the table:
%
%     - ``.Path`` - [char] dotted path of the setting in the preferences structure
%     - ``.Category`` - [char] group shown in the first column of the table
%     - ``.Label`` - [char] name shown in the table
%     - ``.Type`` - [char] editing widget: ``'numeric'`` (numeric field),
%       ``'integer'`` (numeric field rounding to integers), ``'logical'`` (checkbox) or
%       ``'dropdown'`` (dropdown with ``.Items``, value stored as char)
%     - ``.Limits`` - [1x2 double] allowed range of ``'numeric'`` and ``'integer'``
%       settings, ``[]`` otherwise; ``Inf`` is allowed as the upper limit
%     - ``.Items`` - [cell] values of a ``'dropdown'`` setting, ``{}`` otherwise
%     - ``.Description`` - [char] what the setting does, shown under the table, as the
%       tooltip and as the ``_comment`` of the override JSON
%
% Usage:
%   **Example 1** - list the paths of all fine-tuning settings
%
%   .. code-block:: matlab
%
%      tweaks = utils.defaults.generateTweaks();
%      {tweaks.Path}'
%
% See also: utils.defaults.generatePreferences, controllers.Preferences

tweaks = struct('Path', {}, 'Category', {}, 'Label', {}, 'Type', {}, ...
    'Limits', {}, 'Items', {}, 'Description', {});

%% ----------- Zoom -----------
tweaks(end+1) = describeTweak('Tweaks.Zoom.KeyFactor', 'Zoom', 'Zoom step of the Q/W keys', ...
    'numeric', [1.01 10], {}, ...
    ['Factor applied to the magnification by Zoom in/Zoom out: the Q/W keys when the mouse wheel ' ...
     'is set to zoom, and the Change magnification batch action. 2 doubles or halves the ' ...
     'magnification, 1.05 changes it by 5%']);
tweaks(end+1) = describeTweak('Tweaks.Zoom.WheelFactor', 'Zoom', 'Zoom step of the mouse wheel', ...
    'numeric', [1.01 3], {}, ...
    ['Factor applied to the magnification by one step of the mouse wheel, when the mouse wheel ' ...
     'is set to zoom. 1.1 changes the magnification by 10% per step']);

%% ----------- Navigation -----------
tweaks(end+1) = describeTweak('Tweaks.Navigation.SliceStep', 'Navigation', 'Slice step', ...
    'integer', [1 Inf], {}, ...
    ['Number of slices moved by the arrow keys, the Q/W keys and the mouse wheel. ' ...
     'The context menu of the slice slider changes it for the current session only']);
tweaks(end+1) = describeTweak('Tweaks.Navigation.SliceShiftStep', 'Navigation', 'Slice step with Shift', ...
    'integer', [1 Inf], {}, ...
    'Number of slices moved when Shift is held with the arrow keys, the Q/W keys or the mouse wheel');
tweaks(end+1) = describeTweak('Tweaks.Navigation.FrameStep', 'Navigation', 'Time point step', ...
    'integer', [1 Inf], {}, ...
    ['Number of time points moved with Alt + mouse wheel. ' ...
     'The context menu of the time slider changes it for the current session only']);
tweaks(end+1) = describeTweak('Tweaks.Navigation.FrameShiftStep', 'Navigation', 'Time point step with Shift', ...
    'integer', [1 Inf], {}, ...
    'Number of time points moved with Alt + Shift + mouse wheel');

%% ----------- Segmentation -----------
tweaks(end+1) = describeTweak('Tweaks.Segmentation.ToolSizeWheelStep', 'Segmentation', 'Tool size step of Ctrl + mouse wheel', ...
    'integer', [1 100], {}, ...
    ['Change of the brush radius, the Membrane ClickTracker width or the MagicWand range ' ...
     'for one step of Ctrl + mouse wheel']);
tweaks(end+1) = describeTweak('Tweaks.Segmentation.ToolSizeWheelShiftStep', 'Segmentation', 'Tool size step of Ctrl + Shift + mouse wheel', ...
    'integer', [1 100], {}, ...
    'Change of the tool size for one step of Ctrl + Shift + mouse wheel');

%% ----------- Image processing -----------
tweaks(end+1) = describeTweak('ImageArithmetic.NoStoredActions', 'Image processing', 'Image arithmetic history length', ...
    'integer', [1 100], {}, ...
    'Number of recent expressions remembered by the Image arithmetic tool');

end

%% ------------------------------------------------------------------------
function tweak = describeTweak(path, category, label, type, limits, items, description)
% one element of the tweaks struct array; Items is wrapped so that a cell does not
% expand the struct into an array
tweak = struct('Path', path, 'Category', category, 'Label', label, 'Type', type, ...
    'Limits', limits, 'Items', {items}, 'Description', description);
end
