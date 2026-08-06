classdef FakeWidget < handle
% FAKEWIDGET - Minimal stand-in for an App Designer widget in headless tests.
%
% A handle object with the properties the MIB controllers read from and write
% to, so a test can hand a controller a widget-less "view" and then assert on
% what the controller rendered:
%
%   .. code-block:: matlab
%
%      rmseLabel = mibtest.helpers.FakeWidget();
%      controller.view = struct('handles', struct('rmseLabel', rmseLabel), 'gui', []);
%      controller.refreshQualityChip();
%      testCase.verifySubstring(rmseLabel.Text, 'Seams disagree');
%
% Handle semantics are the point - a plain struct would take a COPY and the
% controller's writes would go nowhere. Controllers guard every widget access
% (``isfield(view.handles, …)`` / ``hasWidget``), so only the widgets a test
% actually asserts on need to be present in ``handles``.
%
% See also: controllers.Stitching.refreshQualityChip, controllers.StitchingInspector.hasWidget

    properties
        Text = ''
        % label / button caption
        Value
        % edit field, checkbox, dropdown or state-button value
        Items = {}
        % dropdown / listbox items
        Data
        % uitable contents
        Selection
        % uitable selected row(s)
        ColumnName
        % uitable column headers
        ColumnWidth
        % uitable column widths
        BackgroundColor = 'none'
        % background colour ([r g b] or 'none')
        FontColor = [0 0 0]
        % font colour [r g b]
        Tooltip = ''
        % hover text
        Enable = 'on'
        % 'on' | 'off'
        Visible = 'on'
        % 'on' | 'off'
    end
end
