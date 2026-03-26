function histScale_Callback(obj)
% function histScale_Callback(obj)
% Toggle the histogram Y axis between logarithmic and linear scale.
%
% Reads obj.view.handles.logScale checkbox value: true = log, false = linear.
% Called on checkbox change and after every histogram redraw.
%
%|
% @b Examples:
% @code obj.histScale_Callback();  // refresh scale after redraw @endcode

% Updates
%

if obj.view.handles.logScale.Value
    obj.view.handles.histogram.YScale = 'log';
else
    obj.view.handles.histogram.YScale = 'linear';
end
end
