% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% URL: https://mib.helsinki.fi
% Date: 28.04.2026

classdef PluginWithoutGUI < handle
% PluginWithoutGUI < handle
% Minimalist MIB3 tutorial plugin — demonstrates a plugin that has no
% persistent window of its own.
%
% The plugin thresholds the currently displayed 2D image slice and writes
% the result to the MIB Mask layer.  It is intentionally simple so the
% focus is on the minimum required class structure for a no-GUI plugin.
%
% HOW A NO-GUI PLUGIN DIFFERS FROM A GUI PLUGIN
% ───────────────────────────────────────────────
%   GUI plugin    — constructor creates a ChildView (AppDesigner window),
%                   wires event listeners, and returns.  All work happens
%                   later inside widget callbacks.
%
%   No-GUI plugin — constructor does ALL work synchronously by calling a
%                   Calculate method, then fires CloseEvent to signal
%                   completion.  There is no persistent window or listener.
%
% MINIMUM INTERFACE (required by utils.startController)
% ──────────────────────────────────────────────────────
%   Property   view        — must exist; set to [] (no window)
%   Event      CloseEvent  — fired when the plugin finishes
%   Method     closeWindow — called by parent on shutdown
%
% @b Usage:
% @code
%   % Start from a ribbon button or parent controller:
%   utils.startController(parentObj, 'plugins.Tutorials.PluginWithoutGUI.PluginWithoutGUI');
% @endcode
%
% @b See @b also: README.md, GuiTutorial.m, DemoPlugin.m

    properties
        mibModel
        % Handle to the central MibModel instance.

        view = []
        % Always [] for no-GUI plugins.
        %
        % utils.startController inspects this property after the constructor
        % returns: if it is empty, it re-fires CloseEvent so the parent's
        % childControllers list is cleaned up automatically.
    end

    events
        % CloseEvent — fired at the end of Calculate() and by closeWindow().
        % utils.startController wires a listener so the parent controller
        % removes this plugin from its childControllers list when CloseEvent
        % fires.
        CloseEvent
    end

    methods

        % -----------------------------------------------------------------
        function obj = PluginWithoutGUI(mibModel, varargin)
        % PluginWithoutGUI  Constructor — validate, run, signal completion.
        %
        % The constructor immediately calls Calculate() and then fires
        % CloseEvent.  There is no persistent state after this returns.
        %
        % Parameters:
        % mibModel: handle to MibModel
        % varargin: ignored (utils.startController may pass extra arguments)

            obj.mibModel = mibModel;

            id = obj.mibModel.getActiveId();
            % Always use getActiveId(), never mibModel.id directly:
            % in split-panel mode id is refreshed lazily, so mibModel.id
            % can point at the wrong dataset between user clicks.

            % -----------------------------------------------------------------
            % Guard: virtual datasets stream tiles from disk and do not support
            % the in-memory pixel access used in Calculate().
            % -----------------------------------------------------------------
            if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, ...
                    '!!! Warning !!!', {''}, ...
                    {['This plugin is not compatible with the virtual stacking mode! ' ...
                      'Please switch to memory-resident mode and try again.']}, ...
                    'Not implemented', dlgOpt);
                notify(obj, 'CloseEvent');
                return;
            end

            % Run the operation synchronously — all work happens here.
            obj.Calculate();

            % Signal completion.
            % NOTE: when launched via utils.startController, this notify is
            % a no-op because the CloseEvent listener is not yet wired at
            % this point in the call stack.  startController re-fires
            % CloseEvent itself after the constructor returns (because
            % obj.view is []), which triggers the actual cleanup via
            % utils.purgeChildController.  The explicit notify here handles
            % the case where the plugin is constructed directly (not through
            % startController), e.g. in tests or scripts.
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
        % closeWindow  Respond to an external shutdown request.
        %
        % The parent MibController calls closeWindow() on every open child
        % controller when MIB exits.  For a no-GUI plugin there is nothing
        % to delete, so we just fire CloseEvent.

            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------------
        function Calculate(obj)
        % Calculate  Threshold the current 2D slice and write it to the Mask layer.
        %
        % Steps:
        %   1. Ask the user for a threshold value.
        %   2. Show a progress dialog.
        %   3. Read the full current 2D image slice from MibModel.
        %   4. Threshold each pixel — any channel below threshold → mask = 1.
        %   5. Write the binary mask back to MibModel.
        %   6. Enable the Mask display layer and refresh the canvas.

            id = obj.mibModel.getActiveId();

            % =================================================================
            % STEP 1 — Collect the threshold value from the user.
            %
            % utils.dlgs.inputUniversalDlg is the MIB3 replacement for
            % MIB2's mibInputMultiDlg.
            %
            % Signature:
            %   (parent, header, prompts, defAns, title [, options])
            %
            %   parent  — obj.mibModel.mibGUI (AppContainer) is the correct
            %             parent for all MIB3 dialogs.  Do NOT use a UIFigure
            %             here; using the AppContainer keeps the dialog inside
            %             the main MIB window hierarchy on all platforms.
            %   header  — bold label shown above the input fields; '' = none
            %   prompts — cell array of field labels
            %   defAns  — cell array of default strings for each field
            %   title   — dialog window title
            % =================================================================
            maxInt = obj.mibModel.I{id}.image.maxInt;
            % maxInt = 255 for uint8 images, 65535 for uint16 images.
            % It is read from the dataset so the default threshold is
            % always in the correct range regardless of image type.

            dglOpt.WindowHeight = 180;
            dglOpt.headerLines = 2;
            answer = utils.dlgs.inputUniversalDlg( ...
                obj.mibModel.mibGUI, ...
                'Threshold the current 2D slice and assign the result to the Mask layer.', ...
                {sprintf('Threshold value  (0 \x2013 %d):', maxInt)}, ...
                {num2str(round(maxInt / 2))}, ...
                'Threshold image', dglOpt);
            if isempty(answer); return; end   % user pressed Cancel

            thresholdValue = str2double(answer{1});
            if isnan(thresholdValue) || thresholdValue < 0 || thresholdValue > maxInt
                utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                    sprintf('Please enter a number between 0 and %d.', maxInt), ...
                    'Invalid threshold');
                return;
            end

            % =================================================================
            % STEP 2 — Show a progress dialog.
            %
            % uiprogressdlg is the MIB3 replacement for waitbar.
            % The parent must be obj.mibModel.mibGUI (AppContainer or UIFigure).
            % =================================================================
            waitbarHandle = uiprogressdlg(obj.mibModel.mibGUI, ...
                'Message', 'Thresholding image...', ...
                'Title',   'Plugin Without GUI', ...
                'Value',   0);

            % =================================================================
            % STEP 3 — Read the current 2D image slice.
            %
            % getData2D returns a cell array {roiId}[height, width(, colors)].
            % cell2mat collapses the single-ROI result into a plain matrix.
            %
            % Key arguments:
            %   type       = 'image'
            %   slice_no   = []   — use the current Z slice
            %   orient     = []   — use the current orientation (XY/XZ/YZ)
            %   col_channel= NaN  — retrieve ALL colour channels at once
            %                       Result shape: [height, width, numChannels]
            %
            % options.blockModeSwitch = 0 — always read the FULL slice,
            %   ignoring any viewport zoom/crop.  Set to 1 to process only
            %   the currently visible region (faster for large datasets).
            % =================================================================
            options.blockModeSwitch = 0;
            options.id              = id;
            img = cell2mat(obj.mibModel.getData2D('image', [], [], NaN, options));
            waitbarHandle.Value = 0.5;

            % =================================================================
            % STEP 4 — Compute the binary threshold mask.
            %
            % For multichannel images, a pixel is masked (mask = 1) when ANY
            % channel falls below the threshold.
            %   any(..., 3) — reduce along the colour dimension to get [H, W].
            %
            % The Mask layer stores uint8 values of 0 (background) or 1 (masked).
            % =================================================================
            mask = uint8(any(img < thresholdValue, 3));
            waitbarHandle.Value = 0.9;

            % =================================================================
            % STEP 5 — Write the mask back to MibModel.
            %
            % MIB3 setData2D signature (NOTE: dataset comes FIRST, unlike MIB2):
            %   setData2D(dataset, type, slice_no, orient, col_channel, options)
            %
            % MIB2 → MIB3 changes to watch for:
            %   • Argument order: (type, dataset, ...) → (dataset, type, ...)
            %   • Type string:    'model' → 'labels' (but 'mask' unchanged)
            %   • col_channel is meaningless for the mask layer (single-channel);
            %     pass 0 by convention.
            %   • orient = [] means current orientation; slice_no = [] means
            %     current slice.  Never pass NaN here — use [] instead.
            % =================================================================
            obj.mibModel.setData2D(mask, 'mask', [], [], 0, options);
            
            % =================================================================
            % STEP 6 — Enable the Mask display layer and refresh the canvas.
            %
            % Three coordinated actions are required:
            %   a) obj.mibModel.showMask = true
            %      Tells getRGBimage() to composite the mask over the image.
            %      (MIB2 used notify(mibModel,'showMask') — that event no
            %       longer exists in MIB3.)
            %
            %   b) notify UpdateGuiWidgets with eventdata = {'selectionPanel'}
            %      Updates the "Show Mask" checkbox in the ribbon so the UI
            %      reflects the new showMask state (cosmetic only).
            %
            %   c) notify ShowImage
            %      Redraws the canvas with the updated mask overlay.
            % =================================================================
            obj.mibModel.showMask = true;
            eventdata = core.ToggleEventData({'selectionPanel'});
            notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
            notify(obj.mibModel, 'ShowImage');

            delete(waitbarHandle);
        end

    end
end
