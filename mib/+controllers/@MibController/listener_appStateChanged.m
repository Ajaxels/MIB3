function listener_appStateChanged(obj, src, evtData)
% LISTENER_APPSTATECHANGED - listener_appStateChanged(obj, src, evtData).
%
% Syntax:
%   function listener_appStateChanged(obj, src, evtData)
%
% listener for property change in obj.view.handles.imageViewDocGroup
% At the moment is used to catch selection of the figure-document in the Image View panel

% arguments
%     obj controllers.MibController
%     src matlab.ui.internal.FigureDocumentGroup
%     evtData matlab.ui.container.internal.appcontainer.PropertyChangedEventData
% end

%evtData.PropertyName

switch evtData.PropertyName
    case 'LastSelected'
        % Guard: the AppContainer fires PropertyChanged during shutdown when
        % document panels are being torn down.  If any cImageDoc axes widget
        % is already deleted, abort to avoid cascading "Invalid or deleted
        % object" errors in updateGuiWidgets / showImage.
        if ~isvalid(obj) || isempty(obj.cImageDoc); return; end
        for iShutdownCheck = 1:numel(obj.cImageDoc)
            if ~isvalid(obj.cImageDoc{iShutdownCheck}) || ...
                    isempty(obj.cImageDoc{iShutdownCheck}.handles.imViewAxes) || ...
                    ~isvalid(obj.cImageDoc{iShutdownCheck}.handles.imViewAxes)
                return;
            end
        end

        if ~isempty(obj.view.gui.LastSelectedDocument)
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('MibController.listener_appStateChanged -> selection of a set\n');
            end

            selectedDoc = obj.view.gui.getDocument(obj.view.gui.LastSelectedDocument.documentGroupTag, obj.view.gui.LastSelectedDocument.tag);
            if isprop(selectedDoc, 'Title')
                obj.view.handles.panels.activeDataset.handles.sets.Value = selectedDoc.Title;

                % clear brush offset to recalculate it
                for i=1:numel(obj.cImageDoc)
                    obj.cImageDoc{i}.brushCursorOffset = [];
                end
                obj.cActiveDataset.setsOps_Callbacks([], [], 'sets');
            end
        end
    case 'Region'
        % listeners for movement of the panels to another locations
        switch src.Title
            case 'ROI'
        end
       
end
end
