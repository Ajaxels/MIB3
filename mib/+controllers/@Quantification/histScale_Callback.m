function histScale_Callback(obj)
% HISTSCALE_CALLBACK - Toggle the histogram Y axis between logarithmic and linear scale.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.histScale_Callback()
%
% Reads obj.view.handles.logScale checkbox value: true = log, false = linear.
% Called on checkbox change and after every histogram redraw.
%
% Usage:
%   Example 1::
%
%     obj.histScale_Callback();  // refresh scale after redraw
%

% Updates
%

if obj.view.handles.logScale.Value
    obj.view.handles.histogram.YScale = 'log';
else
    obj.view.handles.histogram.YScale = 'linear';
end
end
