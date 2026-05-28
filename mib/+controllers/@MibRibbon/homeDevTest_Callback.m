function homeDevTest_Callback(obj, hWidget, hData)
% HOMEDEVTEST_CALLBACK - Reserved for MIB developmental purposes.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.homeDevTest_Callback(hWidget, hData)
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeDevTest_Callback: pressed\n');
end


%fprintf('Size of obj.mibModel.I{obj.mibModel.id}.image.sliceSize: %s\n', num2str(size(obj.mibModel.I{obj.mibModel.id}.image.sliceSize)));
%fprintf('Size of obj.mibModel.I{obj.mibModel.id}.labels.sliceSize: %s\n', num2str(size(obj.mibModel.I{obj.mibModel.id}.labels.sliceSize)));
%size(obj.mibModel.I{obj.mibModel.id}.labels.data{1})


%% Benchmark: getRGBimage x 100
% nIter = 100;
% options.blockModeSwitch = 0;
% options.resizeToMagnification = true;
% tStart = tic;
% for k = 1:nIter
%     imgRGB = obj.mibModel.getRGBimage(options); %#ok<NASGU>
% end
% elapsed = toc(tStart);
% fprintf('getRGBimage benchmark: %d iterations in %.3f s — mean %.2f ms/call\n', ...
%     nIter, elapsed, elapsed/nIter*1000);
% return


%obj.mibModel.I{obj.mibModel.id}.labels

% opt.Icon = 'puffin_question';
% opt.DoNotShowAgain = true;
% [answer, dontShow] = utils.dlgs.inputQuestDlg(obj.view.gui, ...
%     'Overwrite existing file?', 'Overwrite', 'Yes', 'No', 'No', opt);
% if strcmp(answer, 'Yes')


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
