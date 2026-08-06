function setDefaultColorPalette(obj, paletteName, colorsNo, randomSeed)
% SETDEFAULTCOLORPALETTE - set default color palette for materials of the model.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setDefaultColorPalette(paletteName, colorsNo, randomSeed)
%
% Input Arguments:
%   - **paletteName** - string with the name of the palette to use, see
%     utils.defaults.generateDefaultPalette for the full list of options;
%     two special values are also accepted:
%   - 'current2default' - copy current model colors to preferences as default
%   - 'default2current' - restore model colors from preferences default
%   - **colorsNo** - *(optional)* numeric, number of required color channels
%   - **randomSeed** - *(optional)* seed for the 'Random Colors' palette; when
%     omitted or empty, a dialog asking for the seed is shown. Use 'shuffle' to
%     seed the generator from the system clock and skip the dialog
%
% Output Arguments:
%
% Usage:
%   **Example 1** - select the default color scheme with 6 colors
%
%   .. code-block:: matlab
%
%      obj.mibModel.setDefaultColorPalette('Default, 6 colors');
%
%   **Example 2** - set "Qualitative (Monte Carlo->Half Baked)" palette with 6 colors
%
%   .. code-block:: matlab
%
%      obj.mibModel.setDefaultColorPalette('Qualitative (Monte Carlo->Half Baked), 3-12 colors', 6);
%
%   **Example 3** - generate random colors without asking for the random seed
%
%   .. code-block:: matlab
%
%      obj.mibModel.setDefaultColorPalette('Random Colors', [], 'shuffle');
%

id = obj.getActiveId();

if nargin < 4; randomSeed = []; end
if nargin < 3; colorsNo = []; end
if nargin < 2; paletteName = 'Default, 6 colors'; colorsNo = 6; end

% update number of colors
if isempty(colorsNo)
    if obj.I{id}.labels.maxMaterials < 256
        colorsNo = numel(obj.I{id}.labels.materialNames);
    else
        colorsNo = 65535;
    end

    if ismember(paletteName, {'Matlab Jet','Matlab Gray','Matlab Bone','Matlab HSV', 'Matlab Cool', 'Matlab Hot'})
        dlgOpt.Type = 'spinner';
        dlgOpt.WindowWidth = 320;
        answer = utils.dlgs.inputSingleDlg(obj.getProgressBarParent(), ...
            sprintf('Please enter number of colors\n(max. value is %d)', obj.I{id}.labels.maxMaterials), ...
            struct('Value', colorsNo, 'Limits', [1 obj.I{id}.labels.maxMaterials], 'Step', 1, 'Round', true), ...
            'Define number of colors', dlgOpt);
        if isempty(answer); return; end
        colorsNo = answer;
    end
end

switch paletteName
    case 'current2default'
        obj.preferences.Colors.ModelMaterialColors = obj.I{id}.labels.materialColors;
        return;
    case 'default2current'
        palette = obj.preferences.Colors.ModelMaterialColors;
    otherwise
        palette = utils.defaults.generateDefaultPalette(paletteName, colorsNo, randomSeed);
        if isempty(palette)
            utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
                'Most likely number of materials in the model is larger than the number of colors in the selected color scheme!', ...
                'Wrong color palette');
            return;
        end
end

if size(palette, 1) < colorsNo
    rng('shuffle');     % randomize generator
    palette2 = colormap(rand([colorsNo-size(palette, 1), 3]));
    palette = [palette; palette2];
end

% update colors for the current model
obj.I{id}.labels.materialColors = palette;

eventdata = core.ToggleEventData({'ribbonModel', 'checkboxes'});
notify(obj, 'UpdateGuiWidgets', eventdata);
notify(obj, 'ShowImage');

end
