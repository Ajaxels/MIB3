function rowHeight = dlgRowHeight(fig)
% DLGROWHEIGHT - Font-aware height in pixels of a single dialog widget row.
%
% Syntax:
%   .. code-block:: matlab
%
%      rowHeight = dlgRowHeight(fig)
%
% Derived from the effective uilabel font size inside the given figure, so rows
% scale with font defaults and DPI instead of a hard-coded 22 px. At the factory
% 12 px font this returns exactly 22 - identical to the previous fixed value.
% The value is cached per session (dialog fonts do not change at runtime).
%
% Input Arguments:
%   - **fig** - [handle] uifigure used to probe the effective uilabel font size
%
% Output Arguments:
%   - **rowHeight** - [numeric] single widget row height in pixels (22 at the 12 px factory font)

persistent cachedRowHeight

if isempty(cachedRowHeight)
    fontSize = 12;
    try
        probe = uilabel(fig, 'Visible', 'off', 'Text', '');
        fontSize = probe.FontSize;
        delete(probe);
    catch
    end
    cachedRowHeight = max(22, round(fontSize * 22 / 12));
end
rowHeight = cachedRowHeight;
end
