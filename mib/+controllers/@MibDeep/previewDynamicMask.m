function previewDynamicMask(obj)
    % function previewDynamicMask(obj)
    % preview results for the dynamic mode

    wb = uiprogressdlg(obj.view.gui, 'Message', 'Please wait...', ...
        'Title', 'Generating blocks');

    % get current image
    getDataOpt.blockModeSwitch = true;
    img = obj.mibModel.getData2D('image', NaN, NaN, NaN, getDataOpt);
    noColors = size(img, 3);
    inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize);
    img = blockedImage(img{1}, ...              % % [height, width, color]
        'Adapter', images.blocked.InMemory);    % convert to blockedimage
    wb.Value = 0.3;
    inputPatchSize(1:2) = inputPatchSize(1:2);
    bls = obj.generateDynamicMaskingBlocks(img, inputPatchSize(1:2), noColors);
    wb.Value = 0.6;

    % show
    figure(randi(1024));
    bigimageshow(img);
    blockedWH = fliplr(bls.BlockSize(1,1:2));
    for ind = 1:size(bls.BlockOrigin,1)
        % BlockOrigin is already in x,y order.
        drawrectangle('Position', [bls.BlockOrigin(ind,1:2),blockedWH]);
    end
    wb.Value = 1;
    delete(wb);
end

