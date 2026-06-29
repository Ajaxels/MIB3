function materialsTable_ContextMenu(obj, menuEntry, selectedData)
% MATERIALSTABLE_CONTEXTMENU - Callback for materials table context menu operations.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.materialsTable_ContextMenu(menuEntry, selectedData)
%
% Handles context menu operations on the materials table (``obj.handles.materialsTable``).
% Supports material visualization, renaming, color selection, quantification, and unlinking.
%
% Input Arguments:
%   - **menuEntry** — [matlab.ui.container.Menu] handle to the pressed context menu entry; operation identified via ``menuEntry.Tag``
%   - **selectedData** — [matlab.ui.eventdata.MenuSelectedData] event data containing the table object (``selectedData.ContextObject``)
%
% Output Arguments:
%   None
%
% **Supported menu operations (menuEntry.Tag):**
%   - ``'materialsTableContextShowSelected'`` — show only the selected material in view
%   - ``'materialsTableContextRename'`` — rename the selected material
%   - ``'materialsTableContextSetColor'`` — open color picker to change material color
%   - ``'materialsTableContextQuant'`` — open quantification dialog for selected material
%   - ``'materialsTableContextUnlink'`` — unlink material from "Add to" reference material
%

% arguments (Input)
%     obj controllers.MibSegmentation
%     menuEntry matlab.ui.container.Menu
%     selectedData matlab.ui.eventdata.MenuSelectedData
% end

if nargin < 3; selectedData = []; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.materialsTable_ContextMenu: context menu for "obj.view.handles.panels.segmentation.handles.materialsTable" -> selected "%s (%s)"\n', menuEntry.Text, menuEntry.Tag);
end

switch menuEntry.Tag
    case 'materialsTableContextShowSelected'
        id = obj.mibModel.getActiveId();
        obj.mibModel.I{id}.showAllMaterials = 1 - obj.mibModel.I{id}.showAllMaterials;    % invert the showAll toggle status
        menuEntry.Checked = logical(obj.mibModel.I{id}.showAllMaterials);
        obj.mibController.showImage();
        
    case 'materialsTableContextRename'
        obj.mibModel.materialsActions('Rename material');
    case 'materialsTableContextSetColor'
        cellIndices = obj.handles.materialsTable.Selection;
        if isempty(cellIndices); return; end
        cellIndices(2) = 1;
        obj.materialsTable_CellSelectionCallback(cellIndices);    
    case 'materialsTableContextQuant'
        obj.mibController.startController('controllers.Quantification');

        %% Materials
    case 'materialsTableContextMatRename'
        obj.mibModel.materialsActions('Rename material');
    case 'materialsTableContextMatAdd'
        obj.mibModel.materialsActions('Add material');
    case 'materialsTableContextMatInsert'
        obj.mibModel.materialsActions('Insert material');
    case 'materialsTableContextMatImport'
        obj.mibModel.materialsActions('Import material');
    case 'materialsTableContextMatSwap'
        obj.mibModel.materialsActions('Swap materials');
    case 'materialsTableContextMatReorder'
        obj.mibModel.materialsActions('Reorder materials');
    case 'materialsTableContextMatExport'
        obj.mibModel.materialsActions('Export material');
    case 'materialsTableContextMatSave'
        obj.mibModel.materialsActions('Save material to file');
    case 'materialsTableContextMatRemove'
        obj.mibModel.materialsActions('Remove material');

        %% Render section...
    case 'materialsTableContextRenMIB'
        % render material with MIB volume rendering
        id = obj.mibModel.getActiveId();
        contIndex = obj.mibModel.I{id}.getSelectedMaterialIndex();
        if contIndex == -1
            if obj.mibModel.I{id}.maskExist == 0
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), 'Mask was not found!', 'Missing mask');
                return;
            end
            options.dataType = 'mask';
            options.colorChannel = 1;
        else
            options.dataType = 'labels';
            options.colorChannel = contIndex;
        end
        obj.mibController.startController('controllers.VolRenApp', options);
    
    case 'materialsTableContextRenMat'
        % render material with MIB isosurfaces
        obj.renderIsosurface();

    case 'materialsTableContextRenFiji'
        % render material with Fiji 3D viewer
        id = obj.mibModel.getActiveId();
        options.fillBg = 0;
        contIndex = obj.mibModel.I{id}.getSelectedMaterialIndex();
        if contIndex == -1
            modelData = obj.mibModel.getData3D('mask', [], 3, [], options);
            contIndex = 1;
            modelColors = obj.mibModel.preferences.Colors.MaskColor;
        else
            modelData = obj.mibModel.getData3D('labels', [], 3, [], options);
            if obj.mibModel.I{id}.showAllMaterials == 1; contIndex = 0; end
            modelColors = obj.mibModel.I{id}.labels.materialColors;
        end
        if numel(modelData) > 1
            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                'Please select only one ROI to render!', 'Selection error');
            return;
        end
        utils.fiji.renderModelWithFiji(modelData{1}, contIndex, ...
            obj.mibModel.I{id}.image.pixSize, modelColors, obj.mibModel.getProgressBarParent());


        %% Unlink material from Add to
    case 'materialsTableContextUnlink'
        if strcmp(menuEntry.Checked, 'off')
            % unlink Materials and AddTo columns
            obj.mibModel.I{obj.mibModel.id}.unlinkMaterials = true;
            menuEntry.Checked = 'on';
        else
            % link Materials and AddTo columns
            obj.mibModel.I{obj.mibModel.id}.unlinkMaterials = false;
            menuEntry.Checked = 'off';
        end
        obj.restrictMaterial_Callback();
    

end

end
