%USING_HG2 Determine if the HG2 graphics engine is used
%
%   tf = using_hg2(fig)
%
%IN:
%   fig - handle to the figure in question.
%
%OUT:
%   tf - boolean indicating whether the HG2 graphics engine is being used
%        (true) or not (false).

% 19/06/2015 - Suppress warning in R2015b; cache result for improved performance
% 06/06/2016 - Fixed issue #156 (bad return value in R2016b)
% 21/08/2026 - graphicsversion() was removed from MATLAB, only the release check is left

function tf = using_hg2(fig) %#ok<INUSD> kept for callers passing a figure handle
    persistent tf_cached
    if isempty(tf_cached)
        try
            tf = ~isMATLABReleaseOlderThan('R2014b');
        catch
            tf = false;
        end
        tf_cached = tf;
    else
        tf = tf_cached;
    end
end
