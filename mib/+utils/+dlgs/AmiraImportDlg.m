classdef AmiraImportDlg < handle
    % AmiraImportDlg Controller for Amira Mesh Import Dialog
    %
    % The AmiraImportDlg class is responsible for a dialog to advanced opening of Amira Mesh files.
    % It manages the interaction logic between the model and the App Designer view.
    %
    % Examples:
    %   % Initialize controller
    %   controller = utils.dlgs.AmiraImportDlg(dimxyczt, parentFigure, options.Font);
    %   %   % Run dialog
    %   result = controller.run();
    %
    %   % Result structure contains:
    %   % result.startIndex
    %   % result.endIndex
    %   % result.zstep
    %   % result.xy_step
    %   % result.method
    
    % Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
    % Part of Microscopy Image Browser, http://mib.helsinki.fi
    % Rewritten to Controller class: 05.01.2026
    
    properties (Access = private)
        view        % Handle to the App Designer view
        parentFigure   % Handle to the parent GUI
        dim_xyczt   % Dimensions of the Amira Mesh dataset
        
        % Output State
        output = NaN; 
    end
    
    methods
        function obj = AmiraImportDlg(dimxyczt, parentFigure, Font)
            % Constructor
            % dimxyczt: vector containing dimensions
            % parentFigure: handle to the parent figure/app
            % Font: structure with FontName and FontSize
            
            obj.dim_xyczt = dimxyczt;
            obj.parentFigure = parentFigure;
            
            % Initialize the App Designer view
            % Assuming the view class is named views.AmiraImportGUI
            obj.view = views.AmiraImportGUI();
            
            % Update font size if Font structure is provided
            if obj.view.handles.firstLabel.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.firstLabel.FontName, Font.FontName)
                 utils.fontSizeUpdate(obj.view.gui, Font);
            end
            
            % Initialize UI components
            obj.initView();
            
            % Make sure the GUI is visible
            obj.view.gui.Visible = true;
        end
        
        function result = run(obj)
            % RUN Execute the dialog logic
            % Blocks execution until the user continues or cancels.
            
            % Block execution
            uiwait(obj.view.gui);
            
            % Check if view was closed abruptly (X button)
            if ~isvalid(obj.view)
                result = NaN;
                return;
            end
            
            % Retrieve result
            result = obj.output;
            
            % Cleanup
            delete(obj.view);
        end
    end
    
    methods (Access = private)
        function initView(obj)
            % Initialize view components and callbacks

            % Center the window relative to parent
            utils.moveWindowOutside(obj.view.gui, obj.parentFigure, 'center', 'center');

            % add icon
            obj.view.gui.Icon = 'mib_icon_16px.png';

            % Set Dimensions Text
            textString = sprintf('%d x %d x %d', obj.dim_xyczt(1), obj.dim_xyczt(2), obj.dim_xyczt(4));
            obj.view.handles.datasetDimensionsLabel.Text = textString;
            
            % Set End Index default (dimension 4)
            obj.view.handles.endSliceSpinner.Value = obj.dim_xyczt(4);    
            
            % add limits
            obj.view.handles.startSliceSlice.Limits = [1 obj.dim_xyczt(4)];
            obj.view.handles.zStepSpinner.Limits = [1 obj.dim_xyczt(4)];
            obj.view.handles.endSliceSpinner.Limits = [1 obj.dim_xyczt(4)];
            obj.view.handles.binXYSpinner.Limits = [1 max([obj.dim_xyczt(1) obj.dim_xyczt(2)])];
            obj.view.handles.binZSpinner.Limits = [1 obj.dim_xyczt(4)];
            
            % Attach Callbacks
            obj.view.handles.continueBtn.ButtonPushedFcn = @obj.onContinue;
            obj.view.handles.cancelBtn.ButtonPushedFcn = @obj.onCancel;
            
            % Linked Z-step and Bin-Z fields
            obj.view.handles.zStepSpinner.ValueChangedFcn = @obj.onZStepChange;
            obj.view.handles.binZSpinner.ValueChangedFcn = @obj.onZStepChange;
            
            % Keyboard handling
            obj.view.gui.WindowKeyPressFcn = @obj.onKeyPress;
        end
        
        function onZStepChange(obj, src, ~)
            % Sync handles.zStepSpinner and handles.binZSpinner
            val = src.Value;
            obj.view.handles.binZSpinner.Value = val;
            obj.view.handles.zStepSpinner.Value = val;
        end
        
        function onContinue(obj, ~, ~)
            % Gather data and close
            
            % Collect results from UI
            % Assuming NumericEditFields for numerical inputs
            res.startIndex = obj.view.handles.startSliceSlice.Value;
            res.endIndex = obj.view.handles.endSliceSpinner.Value;
            res.zstep = obj.view.handles.zStepSpinner.Value;
            res.xy_step = obj.view.handles.binXYSpinner.Value;
            
            % Handle Popup/Dropdown
            res.method = obj.view.handles.resizeDropdown.Value;
            
            obj.output = res;
            
            % Resume execution
            uiresume(obj.view.gui);
        end
        
        function onCancel(obj, ~, ~)
            % Cancel operation
            obj.output = NaN;
            uiresume(obj.view.gui);
        end
        
        function onKeyPress(obj, ~, event)
            % Handle Enter and Escape keys
            if strcmp(event.Key, 'escape')
                obj.onCancel();
            elseif strcmp(event.Key, 'return') || strcmp(event.Key, 'enter')
                obj.onContinue();
            end
        end
    end
end
