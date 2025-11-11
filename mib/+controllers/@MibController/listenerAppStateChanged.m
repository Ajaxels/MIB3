function listenerAppStateChanged(obj, src, evtData)
% listenerAppStateChanged(obj, src, evtData)
% listener for property change in obj.view.handles.imageViewDocGroup
% At the moment is used to catch selection of the figure-document in the Image View panel

arguments
    obj controllers.MibController
    src matlab.ui.internal.FigureDocumentGroup
    evtData matlab.ui.container.internal.appcontainer.PropertyChangedEventData
end

switch evtData.PropertyName
    case 'LastSelected'
        if ~isempty(obj.view.gui.LastSelectedDocument)
            selectedDoc = obj.view.gui.getDocument(obj.view.gui.LastSelectedDocument.documentGroupTag, obj.view.gui.LastSelectedDocument.tag);
            if isprop(selectedDoc, 'Title')
                obj.view.handles.panels.datasets.handles.sets.Value = selectedDoc.Title;
                obj.datasetsSetsOps_Callbacks([], [], 'sets');
            end
        end
end
end