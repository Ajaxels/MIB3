function addCallbacks(obj)
% ADDCALLBACKS - Wire all widget callbacks for MembranePixClassifier.

arguments (Input)
    obj controllers.MembranePixClassifier
end

obj.view.gui.CloseRequestFcn   = @(~,~) obj.closeWindow();
obj.view.gui.WindowKeyPressFcn = @(~,e) obj.keyPressCallback(e);

h = obj.view.handles;
h.trainClassifierBtn.ButtonPushedFcn      = @(~,~) obj.trainClassifierBtn_Callback();
h.predictSlice.ButtonPushedFcn            = @(~,~) obj.predictSlice_Callback();
h.saveClassifierBtn.ButtonPushedFcn       = @(~,~) obj.saveClassifierBtn_Callback();
h.wipeTempDirBtn.ButtonPushedFcn          = @(~,~) obj.wipeTempDirBtn_Callback();
h.tempDirSelectBtn.ButtonPushedFcn        = @(~,~) obj.tempDirSelectBtn_Callback();
h.classifierFilenameBtn.ButtonPushedFcn   = @(~,~) obj.classifierFilenameBtn_Callback();
h.helpBtn.ButtonPushedFcn                 = @(~,~) obj.helpBtn_Callback();
h.closeButton.ButtonPushedFcn             = @(~,~) obj.closeWindow();

h.TempDir.ValueChangedFcn                 = @(~,~) obj.tempDirEdit_Callback();
h.ClassifierFilename.ValueChangedFcn      = @(~,~) obj.classifierFilenameEdit_Callback();
h.ContextSize.ValueChangedFcn             = @(src,~) obj.updateBatchOptFromGUI(src);
h.MembraneThickness.ValueChangedFcn       = @(src,~) obj.updateBatchOptFromGUI(src);
h.VotesThreshold.ValueChangedFcn          = @(src,~) obj.updateBatchOptFromGUI(src);
h.ExportVotes.ValueChangedFcn             = @(src,~) obj.updateBatchOptFromGUI(src);
h.SkelClosed.ValueChangedFcn              = @(src,~) obj.updateBatchOptFromGUI(src);
h.ObjectMaterial.ValueChangedFcn          = @(src,~) obj.updateBatchOptFromGUI(src);
h.BackgroundMaterial.ValueChangedFcn      = @(src,~) obj.updateBatchOptFromGUI(src);
h.trainClassifier.ValueChangedFcn   = @(src,~) obj.modeToggle_Callback(src);
h.predictDataset.ValueChangedFcn    = @(src,~) obj.modeToggle_Callback(src);

end
