function gui_Callbacks(obj, source, event) %#ok<INUSD>
% GUI_CALLBACKS - Dispatcher for every Alignment widget callback.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks(source, event)
%
% Routes by ``source.Tag`` to the appropriate action method. Widgets that
% only need to keep ``BatchOpt`` in sync fall through the ``otherwise``
% branch.
%
% Input Arguments:
%   - **obj** — :class:`controllers.Alignment` instance.
%   - **source** — widget handle that fired the event.
%   - **event** — event data (unused).

switch source.Tag
    case 'continueBtn'
        obj.continueBtn_Callback();
    case 'closeBtn'
        obj.closeWindow();
    case 'helpBtn'
        web('http://mib.helsinki.fi/help/main2/ug_gui_menu_dataset_align.html', '-browser');

    case 'Algorithm'
        obj.algorithm_Callback();
        obj.updateBatchOptFromGUI(source);
    case 'BackgroundColor'
        if strcmp(source.Value, 'Custom')
            obj.view.handles.CustomColorValue.Enable = true;
        else
            obj.view.handles.CustomColorValue.Enable = false;
        end
        obj.updateBatchOptFromGUI(source);

    case 'CorrelateWith'
        if strcmp(source.Value, 'Relative to')
            obj.view.handles.CorrelateStep.Enable = true;
        else
            obj.view.handles.CorrelateStep.Enable = false;
        end
        obj.updateBatchOptFromGUI(source);

    case {'minX','minY','maxX','maxY'}
        obj.subwindowEdit_Callback(source);
        obj.updateBatchOptFromGUI(source);

    case 'getSearchWindow'
        obj.getSearchWindow_Callback();

    case 'loadShiftsCheck'
        obj.loadShiftsCheck_Callback();
        obj.updateBatchOptFromGUI(source);

    case 'previewFeaturesBtn'
        if ismethod(obj, 'previewFeaturesBtn_Callback')
            obj.previewFeaturesBtn_Callback();
        else
            utils.dlgs.showErrorDialog(obj.view.gui, ...
                'Feature-preview is not yet ported to MIB3.', 'Alignment');
        end

    case 'Subarea'
        if strcmp(source.Value, 'Manually specified')
            obj.view.handles.minX.Enable = true;
            obj.view.handles.maxX.Enable = true;
            obj.view.handles.minY.Enable = true;
            obj.view.handles.maxY.Enable = true;
            obj.view.handles.getSearchWindow.Enable = true;
        else
            obj.view.handles.minX.Enable = false;
            obj.view.handles.maxX.Enable = false;
            obj.view.handles.minY.Enable = false;
            obj.view.handles.maxY.Enable = false;
            obj.view.handles.getSearchWindow.Enable = false;
        end
        obj.updateBatchOptFromGUI(source);
    case 'SaveShiftsToFile'
        if source.Value
            startingPath = obj.view.handles.saveShiftsXYpath.Value;
            [FileName, PathName] = uiputfile({'*.coefXY', '*.coefXY (Matlab format)'; '*.*', 'All Files'}, 'Select file...', startingPath);
            if FileName == 0; source.Value = false; return; end
            obj.view.handles.saveShiftsXYpath.Value = fullfile(PathName, FileName);
            obj.view.handles.saveShiftsXYpath.Tooltip = fullfile(PathName, FileName);
            obj.view.handles.saveShiftsXYpath.Enable = 'on';
        else
            obj.view.handles.saveShiftsXYpath.Enable = 'off';
        end
        obj.updateBatchOptFromGUI(source);

    case 'HDD_BioformatsReader'
        if isfield(obj.view.handles, 'HDD_BioformatsIndex')
            obj.view.handles.HDD_BioformatsIndex.Enable = ...
                matlab.lang.OnOffSwitchState(source.Value);
        end
        obj.updateBatchOptFromGUI(source);
    case 'HDD_Mode'
        if source.Value
            obj.view.handles.HDD_Panel.Enable = true;
        else
            obj.view.handles.HDD_Panel.Enable = false;
        end
        obj.updateBatchOptFromGUI(source);
    case 'HDD_SelectDirBtn'
        startingPath = obj.view.handles.HDD_InputDir.Value;
        newDir = uigetdir(startingPath, 'Select directory with images');
        if isequal(newDir, 0); return; end
        obj.view.handles.HDD_InputDir.Value = newDir;
        obj.updateBatchOptFromGUI(obj.view.handles.HDD_InputDir);

    otherwise
        obj.updateBatchOptFromGUI(source);
end

end
