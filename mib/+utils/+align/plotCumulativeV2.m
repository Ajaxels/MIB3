function plotCumulativeV2(hFig, noRows, noCols, cumT, cumR, cumS, ...
    affine_params, Depth, transformType)
% PLOTCUMULATIVEV2 - Plot cumulative v2 alignment parameters into a figure.
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.align.plotCumulativeV2(hFig, noRows, noCols, cumT, cumR, cumS, ...
%          affine_params, Depth, transformType)
%
% Shared plotting helper for the interactive v2 smoothing dialog (in-memory and
% BigData paths). Draws translation (always), rotation (rigid/similarity/affine),
% scale (similarity/affine) and the four affine components (affine only).
%
% See also: utils.align.interactiveSmoothingV2

figure(hFig);
clf(hFig);
subplot(noRows, noCols, 1);
plot(2:Depth, cumT(2:end, 1), '.-', 2:Depth, cumT(2:end, 2), '.-');
title('Translation'); legend('x-axis', 'y-axis', 'Location', 'best'); grid on;

if ismember(transformType, {'rigid', 'similarity', 'affine'})
    subplot(noRows, noCols, 2);
    plot(2:Depth, cumR(2:end), '.-'); title('Rotations'); grid on;
end
if ismember(transformType, {'similarity', 'affine'})
    subplot(noRows, noCols, 3);
    plot(2:Depth, cumS(2:end), '.-'); title('Scales'); grid on;
end
if strcmp(transformType, 'affine')
    subplot(noRows, noCols, 5);
    plot(2:Depth, affine_params(2:end, 1), '.-');
    title('Affine a (scaling/shear/rotation, ~1)'); grid on;
    subplot(noRows, noCols, 6);
    plot(2:Depth, affine_params(2:end, 2), '.-');
    title('Affine b (shear/rotation, ~0)'); grid on;
    subplot(noRows, noCols, 7);
    plot(2:Depth, affine_params(2:end, 3), '.-');
    title('Affine c (shear/rotation, ~0)'); grid on;
    subplot(noRows, noCols, 8);
    plot(2:Depth, affine_params(2:end, 4), '.-');
    title('Affine d (scaling/shear/rotation, ~1)'); grid on;
end
end
