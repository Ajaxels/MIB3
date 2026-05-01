function gui_WindowButtonDownFcn(obj)
% GUI_WINDOWBUTTONDOWNFCN - Handle mouse button press events on the histogram axes.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.gui_WindowButtonDownFcn()
%
% Left-click sets the lower histogram limit (obj.histLimits(1));
% right-click sets the upper limit (obj.histLimits(2)).
% Clicks outside the Y axis range are ignored.
% After updating the limits the corresponding highlight1/highlight2 edit
% boxes are updated and objects whose value column falls within
% [histLimits(1), histLimits(2)] are highlighted in the selection layer.
%
% Usage:
%   Example 1::
%
%     % wired in addCallbacks:
%
%   Example 2::
%
%     obj.view.gui.WindowButtonDownFcn = @(~,~) obj.gui_WindowButtonDownFcn();
%

% Updates
%

% only process clicks inside the histogram axes
xy = obj.view.handles.histogram.CurrentPoint;
seltype = obj.view.gui.SelectionType;
ylimits = obj.view.handles.histogram.YLim;
if xy(1,2) > ylimits(2); return; end
if xy(1,2) < ylimits(1); return; end

switch seltype
    case 'normal'   % left-click: set min limit
        obj.histLimits(1) = xy(1,1);
    case 'alt'      % right-click: set max limit
        obj.histLimits(2) = xy(1,1);
end
obj.histLimits = sort(obj.histLimits);

obj.view.handles.highlight1.Value = obj.histLimits(1);
obj.view.handles.highlight2.Value = obj.histLimits(2);
end
