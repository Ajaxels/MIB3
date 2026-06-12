function imOut = fstack_mib(I, options)
% FSTACK_MIB - Extended depth-of-field focus stacking for MIB.
%
% Syntax:
%   .. code-block:: matlab
%
%       imOut = utils.fstack_mib(I)
%       imOut = utils.fstack_mib(I, options)
%
% Generates an extended depth-of-field image from a focus sequence using the
% noise-robust selective all-in-focus algorithm [1].
%
% Input Arguments:
%   - **I** — image stack ``[height, width, colors, depth]``; numeric array.
%   - **options** — *(optional)* struct with algorithm parameters:
%
%     - ``.nhsize``      — focus-measure window size (default ``9``).
%     - ``.focus``       — vector of focus values per frame
%                          (default ``1:depth``).
%     - ``.alpha``       — scalar in ``(0,1]`` (default ``0.2``). See [1].
%     - ``.sth``         — scalar threshold (default ``13``). See [1].
%     - ``.showWaitbar`` — show progress waitbar (default ``true``).
%
% Output Arguments:
%   - **imOut** — single-plane all-in-focus image ``[height, width, colors]``,
%                 same class as ``I``.
%
% References:
%   [1] Pertuz et al. "Generation of all-in-focus images by noise-robust
%   selective fusion of limited depth-of-field images." IEEE Trans. Image
%   Process, 22(3):1242-1251, 2013.
%
% .. note::
%   Original ``fstack`` by Said Pertuz (MATLAB Central FEX 55115).
%   Adapted for MIB by Ilya Belevich, 08.02.2019.

% Updates
%

if nargin < 2; options = struct(); end
if ~isfield(options, 'nhsize');      options.nhsize = 9; end
if ~isfield(options, 'focus');       options.focus = 1:size(I, 4); end
if ~isfield(options, 'alpha');       options.alpha = 0.2; end
if ~isfield(options, 'sth');         options.sth = 13; end
if ~isfield(options, 'showWaitbar'); options.showWaitbar = true; end

if options.showWaitbar
    waitbarHandle = waitbar(0, 'Initializing...', 'Name', 'Extended depth-of-field focus stacking');
end
tic;
height = size(I, 1);
width  = size(I, 2);
colors = size(I, 3);
depth  = size(I, 4);

if options.showWaitbar; waitbar(0.1, waitbarHandle, 'Calculating F-measure...'); end
fm = zeros(height, width, depth);
for p = 1:depth
    im = mean(double(I(:,:,:,p)), 3);
    fm(:,:,p) = gfocus(im, options.nhsize);
end

%--- Compute S-measure ---
if options.showWaitbar; waitbar(0.35, waitbarHandle, 'Calculating S-measure...'); end
[u, s, A, fmax] = gauss3P(options.focus, fm);

err = zeros(height, width);
for p = 1:depth
    err = err + abs(fm(:,:,p) - A.*exp(-(options.focus(p)-u).^2./(2*s.^2)));
    fm(:,:,p) = fm(:,:,p)./fmax;
end
h = fspecial('average', options.nhsize);
inv_psnr = imfilter(err./(depth*fmax), h, 'replicate');

S = 20*log10(1./inv_psnr);
S(isnan(S)) = min(S(:));

if options.showWaitbar; waitbar(0.65, waitbarHandle, 'Calculating weights...'); end
phi = 0.5*(1 + tanh(options.alpha*(S - options.sth)))/options.alpha;
phi = medfilt2(phi, [3 3]);

%--- Compute weights ---
fun = @(phi, fm) 0.5 + 0.5*tanh(phi.*(fm - 1));
for p = 1:depth
    fm(:,:,p) = fun(phi, fm(:,:,p));
end

%--- Fuse images ---
if options.showWaitbar; waitbar(0.85, waitbarHandle, 'Fusing images...'); end
fmn = sum(fm, 3);
imOut = zeros([height, width, colors], class(I));
for colorChannel = 1:colors
    imOut(:,:,colorChannel) = sum(squeeze(double(I(:,:,colorChannel,:))).*fm, 3)./fmn;
end

if options.showWaitbar; waitbar(1, waitbarHandle); delete(waitbarHandle); end
toc;
end

% -------------------------------------------------------------------------
function [u, s, A, Ymax] = gauss3P(x, Y)
% Fast 3-point Gaussian interpolation.
[height, width, depth] = size(Y);
if depth < 5
    STEP = 1;
else
    STEP = 2;
end
[Ymax, I] = max(Y, [], 3);
[IN, IM] = meshgrid(1:width, 1:height);
Ic = I(:);
Ic(Ic <= STEP) = STEP + 1;
Ic(Ic >= depth - STEP) = depth - STEP;
Index1 = sub2ind([height, width, depth], IM(:), IN(:), Ic - STEP);
Index2 = sub2ind([height, width, depth], IM(:), IN(:), Ic);
Index3 = sub2ind([height, width, depth], IM(:), IN(:), Ic + STEP);
Index1(I(:) <= STEP) = Index3(I(:) <= STEP);
Index3(I(:) >= STEP) = Index1(I(:) >= STEP);
x1 = reshape(x(Ic(:) - STEP), height, width);
x2 = reshape(x(Ic(:)),        height, width);
x3 = reshape(x(Ic(:) + STEP), height, width);
y1 = reshape(log(Y(Index1)), height, width);
y2 = reshape(log(Y(Index2)), height, width);
y3 = reshape(log(Y(Index3)), height, width);
c = ((y1-y2).*(x2-x3) - (y2-y3).*(x1-x2)) ./ ...
    ((x1.^2-x2.^2).*(x2-x3) - (x2.^2-x3.^2).*(x1-x2));
b = ((y2-y3) - c.*(x2-x3).*(x2+x3)) ./ (x2 - x3);
s = sqrt(-1./(2*c));
u = b.*s.^2;
a = y1 - b.*x1 - c.*x1.^2;
A = exp(a + u.^2./(2*s.^2));
end

% -------------------------------------------------------------------------
function FM = gfocus(im, WSize)
% Focus measure using grey-level local variance.
MEANF = fspecial('average', [WSize WSize]);
U  = imfilter(im, MEANF, 'replicate');
FM = (im - U).^2;
FM = imfilter(FM, MEANF, 'replicate');
end
