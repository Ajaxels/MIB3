 # MIB AppDesigner Plugin

*Back to [MIB](../../../index.md) | [User Interface](../../index.md) | [Plugins](../index.md) | [Tutorials](index.md)*

---

## Overview

![MIB plugin with GUI](images/appdesigner.png){.on-glb align=left width="300"}

The **MIB App Design Plugin** is a tutorial that demonstrates how to create plugins 
for **Microscopy Image Browser (MIB)** 
[appdesigner](https://se.mathworks.com/help/releases/R2024b/matlab/ref/appdesigner.html)-based graphical interface. 
<br>It demonstrates how to build a simple plugin that shows how to use various widgets.

<div class="clear-float"></div>

## Plugin filenames definition

A plugin built with the AppDesigner GUI typically includes the following files:

* `[PLUGIN-NAME]Controller.m`, controller of the plugin with the main logic and functions
* `[PLUGIN-NAME]GUI.mlapp`, figure file generated using MATLAB
   [AppDesigner](https://se.mathworks.com/help/releases/R2024b/matlab/ref/appdesigner.html)
   tool for GUI framework development.
 
!!! info 
    where `[PLUGIN-NAME]` is the name of the plugin. 

!!! warning
    This plugin name (`[PLUGIN-NAME]`) should match with the name of the directory where 
    the plugin is located.

??? info "Example" 
    For example `mibPluginController.m`:
    
    - `[PLUGIN-NAME]` -> `mibPlugin`, located under `Plugins/Tutorials/mibPlugin` directory
    - Full path: `MIB/Plugins/Tutorials/mibPlugin/mibPluginController.m`
    The same applies to `mibPluginGUI.mlapp` 

??? info "Plugins with GUI made using guide"

    [guide](https://se.mathworks.com/help/releases/R2024b/matlab/ref/guide.html) is the original
    MATLAB framework for development of GUI applications.<br>
    Example of the guide-based plugin is located under [Plugins/Tutorials/mibPlugin](mib-plugin.md) 
    and [Plugins/Tutorials/GuiTutorial](gui-tutorial.md) 

??? info "Plugins without GUI"
    A plugin without a GUI consists of a single file named `[PLUGIN-NAME]Controller.m`, 
    where `[PLUGIN-NAME]` is the name of the plugin. See more [here](mib-plugin-without-gui.md).

## Sections of mibAppDesignPluginController.m

### properties

Use this section to define properties for the plugin class. 
These properties will be available to all functions within the plugin class.<br>
??? abstract "Code for properties"
    ```matlab
    properties
        mibModel
        % handles to mibModel
        View
        % handle to the view / mibAppDesignPluginGUI
        listener
        % a cell array with handles to listeners
        BatchOpt
        % a structure compatible with batch operation
        % name of each field should be displayed in a tooltip of GUI
        % it is recommended that the Tags of widgets match the name of the
        % fields in this structure
        % .Parameter - [editbox], char/string 
        % .Checkbox - [checkbox], logical value true or false
        % .Dropdown{1} - [dropdown],  cell string for the dropdown
        % .Dropdown{2} - [optional], an array with possible options
        % .Radio - [radiobuttons], cell string 'Radio1' or 'Radio2'...
        % .ParameterNumeric{1} - [numeric editbox], cell with a number 
        % .ParameterNumeric{2} - [optional], vector with limits [min, max]
        % .ParameterNumeric{3} - [optional], string 'on' - to round the value, 'off' to do not round the value
    end
    ``` 

### events

This plugin has a single event that is triggered when the plugin is closed.
??? abstract "Code for events"
    ```matlab
    events
        %> Description of events
        closeEvent
        % event firing when plugin is closed
    end
    ```
    
### methods (static)

This section contains a function that listens for `updateGuiWidgets` event from mibModel. When it comes, 
the plugin refreshes itself using `obj.updateGuiWidgets()` function. 
??? abstract "Code for static methods"
    ```matlab
    methods (Static)
        function ViewListner_Callback(obj, src, evnt)
            switch evnt.EventName
                case {'updateGuiWidgets'}
                    obj.updateWidgets();
            end
        end
    end
    ```


### constructor
Constructor is the first function <br>
`function obj = mibAppDesignPluginController(mibModel, varargin)`<br>
initialized when the plugin starts.

`mibModel` that holds data classes of MIB is passed as a parameter and assigned into `obj.mibModel` 
variable available to all functions of the plugin:<br>
`obj.mibModel = mibModel;    % assign model`

<div class="h4-like">Initialization of default obj.BatchOpt parameters</div>

In order to be compatible with the batch processing operations and work in general, the 
default values for the plugin widgets should be predefined in this section using obj.BatchOpt structure.<br>
Each field in the structure corresponds to a widget tag in `mibAppDesignPluginGUI.mlapp`.<br>
Depending on widget type, their initialization may be different, check this section for examples of initialization
patterns for various widget types:

??? abstract "Initialization of obj.BatchOpt structure"

    ```matlab
    %% fill the BatchOpt structure with default values
    % fields of the structure should correspond to the starting
    % text in the each widget tooltip.
    % For example, this demo template has an edit box, where the
    % tooltip starts with "Parameter:...". Text Parameter
    % indicates field of the BatchOpt structure that defines value
    % for this widget
    obj.BatchOpt.Parameter = 'my parameter'; 	% edit box
    obj.BatchOpt.Checkbox = true; 				% checkbox
    obj.BatchOpt.Dropdown = {'Option 3'}; 		% dropdown selected value
    obj.BatchOpt.Dropdown{2} = {'Option 1', 'Option 2', 'Option 3'}; % dropdown options
    obj.BatchOpt.Radio = {'Radio2'};  % selected radio button value
    obj.BatchOpt.ParameterNumeric{1} = 512.125;     % numeric edit box or spinner
    obj.BatchOpt.ParameterNumeric{2} = [0 1024];    % possible limits value
    obj.BatchOpt.ParameterNumeric{3} = 'off';    % round the numeric value
    obj.BatchOpt.showWaitbar = true; 	% show or not the progress waitbar
    obj.BatchOpt.id = obj.mibModel.Id;  % optional        
    ```

The initialization of `obj.BatchOpt` is followed with initialization of the section and action names 
to be compatible with `MIB\Classes\@mibBatchController\mibAppDesignPluginController.m` and 
[Batch processing](../../ribbon/home/home-batchprocessing.md) 

??? abstract "Plugin information for Batch processing"
    
    Optionally:<br>
    ```matlab
    %% part below is only valid for use of the plugin from MIB batch controller
    % comment it if intended use not from the batch mode
    obj.BatchOpt.mibBatchSectionName = 'Menu -> Plugins';    % section name for the Batch
    obj.BatchOpt.mibBatchActionName = 'mibAppDesignPlugin';           % name of the plugin
    ```

Define tooltip text that appears when hovering over each widget. These tooltips help users understand the function of each GUI element.

??? abstract "Tooltip descriptions"

    ```matlab
    % tooltips that will accompany the BatchOpt
    obj.BatchOpt.mibBatchTooltip.Parameter = sprintf('Provide text or number as string');
    obj.BatchOpt.mibBatchTooltip.Checkbox = sprintf('Specify checkboxes as logicals');
    obj.BatchOpt.mibBatchTooltip.Popup = sprintf('Popups populated using cells');
    obj.BatchOpt.mibBatchTooltip.Radio = sprintf('Selection of radio buttons, as cell with the handle of the target radio button');
    obj.BatchOpt.mibBatchTooltip.showWaitbar = sprintf('Show or not waitbar');
    ```

<div class="h4-like">Batch processing compatibility block</div>

The next section defines how the plugin interacts with the **Batch Processing** dialog 
or to run the plugin from the **Batch processing** dialog.<br>

* `obj.returnBatchOpt()` function is used to return the plugin parameters to the **Batch processing** dialog<br>
* `obj.BatchOpt = updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);` updates `obj.BatchOpt` using 
the provided `BatchOptIn` from the **Batch processing** dialog. 
* `obj.Calculate();` when started from the **Batch processing** dialog run the function and close the plugin dialog.

??? abstract "Batch processing block"
    
    ```matlab
    %% add here a code for the batch mode, for example
    % when the BatchOpt stucture is provided the controller will
    % use it as the parameters, and performs the function in the
    % headless mode without GUI
    if nargin == 3
        BatchOptIn = varargin{2};
        if isstruct(BatchOptIn) == 0 
            if isnan(BatchOptIn)     % when varargin{2} == NaN return possible settings
                obj.returnBatchOpt();   % obtain Batch parameters
            else
                errordlg(sprintf('A structure as the 3rd parameter is required!')); 
            end
            notify(obj, 'closeEvent'); 
            return
        end
        % add/update BatchOpt with the provided fields in BatchOptIn
        % combine fields from input and default structures
        obj.BatchOpt = updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                
        obj.Calculate(); % run the main plugin function
        notify(obj, 'closeEvent'); % close the dialog
        return;
    end
    ```
??? warning "Optional modification of Batch processing controller"

    In order to use the plugin with [Batch processing](../../ribbon/home/home-batchprocessing.md) dialog, the 
    corresponding section needs to be added into `MIB\Classes\@mibBatchController\mibAppDesignPluginController.m`<br>
    Navigate to <br>
    ```matlab
    function obj = mibBatchController(mibModel, varargin)
    ...
    obj.Sections(secIndex).Name = 'Menu -> Plugins';
    ```
    Add the following code: <br>
    ```matlab
    obj.Sections(secIndex).Actions(actionId).Name = 'mib App Design Plugin [any suitable name]';
    obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''mibAppDesignPluginController'', [], Batch);'; actionId = actionId + 1;
    ```        

<div class="h4-like">Plugin initialization block</div>

- `guiName = 'mibAppDesignPluginGUI';` define plugin name
- `obj.View = mibChildView(obj, guiName); % initialize the view` initialize the view provided by `mibAppDesignPluginGUI.mlapp`
- `obj.View.gui = moveWindowOutside(obj.View.gui, 'left');` move the plugin window to a side of the main MIB window
- update the font size
??? abstract "Update font size"
   
    ```matlab
    global Font;
    if ~isempty(Font)
         if obj.View.handles.infoText.FontSize ~= Font.FontSize ...
             || ~strcmp(obj.View.handles.infoText.FontName, Font.FontName)
             mibUpdateFontSize(obj.View.gui, Font);
         end
    end
    ```
- `obj.updateWidgets();` function is triggered at the plugin startup and whenever `updateGuiWidgets` event comes
- `obj.View = updateGUIFromBatchOpt_Shared(obj.View, obj.BatchOpt);` update GUI widgets using `obj.BatchOpt` structure
- `obj.listener{1} = addlistener(obj.mibModel, 'updateGuiWidgets', @(src,evnt) obj.ViewListner_Callback(obj, src, evnt));` add
listener to catch events generated by main MIB window.

### closeWindow
You can define custom behavior that runs when the user closes the plugin window.<br>
By default, the plugin notifies the main MIB controller that it gets closed: `notify(obj, 'closeEvent');`

??? abstract "Code of closeWindow function"

    ```matlab
    function closeWindow(obj)
        % closing mibAppDesignPluginController window
        if isvalid(obj.View.gui)
            delete(obj.View.gui);   % delete childController window
        end
            
        % delete listeners, otherwise they stay after deleting of the
        % controller
        for i=1:numel(obj.listener)
            delete(obj.listener{i});
        end
            
        notify(obj, 'closeEvent');      % notify mibController that this child window is closed
    end
    ```

### updateWidgets
Function that updates the plugin GUI widgets from `obj.BatchOpt` triggered at the plugin startup and whenever `updateGuiWidgets` event comes

??? abstract "Code of updateWidgets function"

    ```matlab
    function updateWidgets(obj)
        % function updateWidgets(obj)
        % update widgets of this window
            
        % updateWidgets normally triggered during change of MIB
        % buffers, make sure that any widgets related changes are
        % correctly propagated into the BatchOpt structure
        if isfield(obj.BatchOpt, 'id'); obj.BatchOpt.id = obj.mibModel.Id; end
            
        % when elements GIU needs to be updated, update obj.BatchOpt
        % structure and after that update elements of GUI by the
        % following function
        obj.View = updateGUIFromBatchOpt_Shared(obj.View, obj.BatchOpt);    %
          
        fprintf('childController:updateWidgets: %g\n', toc);
    end
    ```
### updateBatchOptFromGUI
This is a standard callback function for widgets of the GUI window. Upon change of a widget, it is triggered and
updates the corresponding field of `obj.BatchOpt`

??? abstract "Code of updateBatchOptFromGUI function"

    ```matlab
    function updateBatchOptFromGUI(obj, event)
        % function updateBatchOptFromGUI(obj, event)
        %
        % update obj.BatchOpt from widgets of GUI
        % use an external function (Tools\updateBatchOptFromGUI_Shared.m) that is common for all tools
        % compatible with the Batch mode
        %
        % Parameters:
        % event: event from the callback
            
        obj.BatchOpt = updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
    end
    ```

### returnBatchOpt
Return obj.BatchOpt structure to the **Batch processing** dialog

??? abstract "Code of returnBatchOpt function"

    ```matlab
    function returnBatchOpt(obj, BatchOptOut)
        % return structure with Batch Options and possible configurations
        % via the notify 'syncBatch' event
        % Parameters:
        % BatchOptOut: a local structure with Batch Options generated
        % during Continue callback. It may contain more fields than
        % obj.BatchOpt structure
        % 
        if nargin < 2; BatchOptOut = obj.BatchOpt; end
            
        if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end  % remove id field
        % trigger syncBatch event to send BatchOptOut to mibBatchController 
        eventdata = ToggleEventData(BatchOptOut);
        notify(obj.mibModel, 'syncBatch', eventdata);
    end
    ```
### Calculate function
This is the main function of the plugin demonstrating usage of obj.BatchOpt to acquire current values of widgets of 
the plugin GUI.

## Adapting the function to a new plugin
Perform the following operations to use this plugin as a template for a new plugin.

### Copy and rename template files

* Create a folder for your plugins under `MIB/Plugins/` for example `MyPlugins` so that the full path is<br>
`MIB/Plugins/MyPlugins`
* Create a subfolder under `MIB/Plugins/MyPlugins` and name it with the name of your new plugin
(e.g.`MIB/Plugins/MyPlugins/myThirdPlugin`) 
* Copy `mibAppDesignPluginController.m` and `mibAppDesignPluginGUI.mlapp` to 
`MIB/Plugins/MyPlugins/myThirdPlugin`
* Rename `mibAppDesignPluginController.m` to `myThirdPluginController.m`

### Rename plugin name in the *Controller.m

* Open `myThirdPluginController.m` in MATLAB 
* Do *Find and Replace* to search for `mibAppDesignPlugin` and replace with `myThirdPlugin`, 
++ctrl+f++ key shortcut.
* Edit `Calculate function` to implement your desired functionality  
* Save the plugin

### Modify and resave *GUI.mlapp

* Type `appdesigner mibAppDesignPluginGUI.mlapp` to open it in MATLAB appdesigner.
!!! warning
    You may need to change the current MATLAB folder to the plugin directory otherwise
    it may open the previous version of the plugin in `Tutorials\mibPlugin\myThirdPlugin`
* Modify the plugin as needed
* Resave the **mlapp** as `myThirdPluginGUI.mlapp`

---

*Back to [MIB](../../../index.md) | [User Interface](../../index.md) | [Plugins](../index.md) | [Tutorials](index.md)*