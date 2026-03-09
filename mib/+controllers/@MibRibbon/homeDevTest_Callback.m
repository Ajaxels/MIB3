function homeDevTest_Callback(obj, hWidget, hData)
% function homeDevTest_Callback(obj, hWidget, hData)
% Reserved for MIB developmental purposes

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeDevTest_Callback: pressed\n');
end

%% Test Zarr3 from remote source
% BatchOptIn.Filenames = {'https://uk1s3.embassy.ebi.ac.uk/idr/zarr/v0.5/idr0066/ExpA_VIP_ASLM_on.zarr'};
% BatchOptIn.Filenames = {'https://uk1s3.embassy.ebi.ac.uk/idr/zarr/v0.5/idr0051/180712_H2B_22ss_Courtney1_20180712-163837_p00_c00_preview.zarr'};
% BatchOptIn.Filenames = {'https://uk1s3.embassy.ebi.ac.uk/idr/zarr/v0.5/idr0083/9822152.zarr'};
% obj.mibModel.loadImages('Combine datasets', BatchOptIn);
% obj.mibModel.I{obj.mibModel.id}.image.viewPort.max = 10000;
% obj.mibController.showImage();


%obj.mibController.mibModel.clearSelection();
%obj.mibController.mibModel.clearLayer('selection');
%obj.mibController.mibModel.clearLayer('selection', '2D, Slice');
%obj.mibController.mibModel.I{obj.mibController.mibModel.id}.clearLayer('selection');
end