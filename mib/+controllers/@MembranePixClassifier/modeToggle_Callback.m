function modeToggle_Callback(obj, hObject)
% MODETOGGLE_CALLBACK - Switch between Train and Predict modes.
%
% Enables/disables training-specific controls and updates the main
% action button label to match the current mode.

arguments (Input)
    obj     controllers.MembranePixClassifier
    hObject
end

h = obj.view.handles;

% prevent deselecting the already-active toggle by clicking it again
if ~hObject.Value
    hObject.Value = true;
    return;
end

switch hObject.Tag
    case 'trainClassifier'
        h.predictDataset.Value   = false;
        h.objectText.Enable            = 'on';
        h.backgroundText.Enable        = 'on';
        h.ObjectMaterial.Enable        = 'on';
        h.BackgroundMaterial.Enable    = 'on';
        h.membrThickText.Enable        = 'on';
        h.MembraneThickness.Enable     = 'on';
        h.ContextSize.Enable           = 'on';
        h.contextSizeText.Enable       = 'on';
        h.trainClassifierBtn.Text      = 'Train classifier';
        h.predictSlice.Visible         = 'off';
        obj.BatchOpt.Mode{1}           = 'trainClassifier';
    case 'predictDataset'
        h.trainClassifier.Value  = false;
        h.objectText.Enable            = 'off';
        h.backgroundText.Enable        = 'off';
        h.ObjectMaterial.Enable        = 'off';
        h.BackgroundMaterial.Enable    = 'off';
        h.membrThickText.Enable        = 'off';
        h.MembraneThickness.Enable     = 'off';
        h.ContextSize.Enable           = 'off';
        h.contextSizeText.Enable       = 'off';
        h.trainClassifierBtn.Text      = 'Predict dataset';
        h.predictSlice.Visible         = 'on';
        obj.BatchOpt.Mode{1}           = 'predictDataset';
end

end
