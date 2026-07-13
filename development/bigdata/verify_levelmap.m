function verify_levelmap()
% VERIFY_LEVELMAP - end-to-end checks for the BigData level-map manager on a real
% WSI (CMU-1.ndpi). Run via the MATLAB MCP run_matlab_file. Errors on any failure;
% prints "ALL LEVELMAP CHECKS PASSED" on success.
%
% Covers: halo-free read at the painting zoom, zoom-in recompute + cache,
% selection-over-material (Bug B), clear at low mag, Save materialization,
% side-file persistence + fallback, and bounded per-edit cost.

addpath('C:\Matlab\MIB3\mib'); rehash;
io.BioFormats.Config.setLibrary('mib'); io.zarr.Config.setSmoothing(false);
f = 'C:\Matlab2\Data\FileFormats\czi\CMU-1.ndpi';
o0 = struct('datasetMode','BigData','readerFamily','BioFormats','silentMode',true, ...
    'ParentFigure',[],'mibPath','C:\Matlab\MIB3\mib');
Ld = io.loaders.BioFormatsVirtualSetupLoader(o0);
[mi, fl] = Ld.loadMetadata({f}, o0); [img, mi] = Ld.loadImages(fl, mi, o0);
io_ = core.MibBigDataImage(img, mi);
bm = core.MibImage.initializeImgInfo('pixSize', io_.pixSize, 'Height', io_.height, ...
    'Width', io_.width, 'Depth', io_.depth, 'Time', io_.time, 'Colors', 1);
sp = fullfile(tempdir, 'verify_levelmap.zarr3');
if isfolder(sp); rmdir(sp, 's'); end
if isfile([sp '.levelmap.mat']); delete([sp '.levelmap.mat']); end

lb = core.MibBigDataLabels([], bm);
lb.createStore([io_.height, io_.width, io_.depth], sp, io_.pyramid);
H = lb.height; W = lb.width;

% ---- 1. halo-free read at a non-coarsest painting zoom ----
mf = 4; o = struct('magFactor',mf,'x',[1 W],'y',[1 H],'z',[1 1],'t',[1 1]);
dyx = round([H W]/mf); [xx,yy] = meshgrid(1:dyx(2),1:dyx(1));
disk = uint8((xx-dyx(2)/2).^2 + (yy-dyx(1)/2).^2 <= 200^2);
lb.setData63(disk, 'selection', 3, [], o);
back = squeeze(lb.getData63('selection', 3, [], o));
diskR = imresize(disk, size(back), 'nearest');
halo = nnz(back & ~imdilate(diskR, strel('disk',2)));
agree = 100*nnz(back & diskR)/max(nnz(back), nnz(diskR));
assert(halo == 0, 'FAIL halo: %d spurious px', halo);
assert(agree > 97, 'FAIL agreement: %.1f%%', agree);
fprintf('1 halo-free read: halo=%d agreement=%.1f%%\n', halo, agree);

% ---- 2. zoom-in recompute + cache ----
cyF = round(H/2); cxF = round(W/2);
o1 = struct('magFactor',1,'y',[cyF-2048 cyF+2048],'x',[cxF-2048 cxF+2048],'z',[1 1],'t',[1 1]);
s1 = squeeze(lb.getData63('selection', 3, [], o1));
assert(any(s1(:)), 'FAIL zoom-in lost edit');
assert(min(lb.matLevel(lb.matLevel>0)) == 1, 'FAIL zoom-in did not materialize to level 1');
s1b = squeeze(lb.getData63('selection', 3, [], o1));
assert(isequal(s1, s1b), 'FAIL cached read differs');
fprintf('2 zoom-in recompute+cache: px=%d, cached read identical\n', nnz(s1));

% ---- 3. selection over material leaves material intact (Bug B) ----
lb.clearLayer('selection', [], [], [1 1], [1 1], mf);
matBox = uint8(zeros(dyx)); matBox(cyF/mf-100:cyF/mf+100, cxF/mf-100:cxF/mf+100) = 1; %#ok<*NASGU>
% rebuild the box cleanly at level-mf display coords (centered)
matBox = uint8(zeros(dyx));
by = round(dyx(1)/2); bx = round(dyx(2)/2);
matBox(by-100:by+100, bx-100:bx+100) = 1;
lb.setData63(matBox, 'labels', 3, 1, o);
labBefore = nnz(squeeze(lb.getData63('labels', 3, [], o)) == 1);
selOver = uint8(zeros(dyx)); selOver(by-50:by+50, bx-50:bx+50) = 1;
lb.setData63(selOver, 'selection', 3, [], o);
labAfter = nnz(squeeze(lb.getData63('labels', 3, [], o)) == 1);
assert(labAfter == labBefore, 'FAIL Bug B: material %d -> %d', labBefore, labAfter);
fprintf('3 selection-over-material: material px %d (unchanged)\n', labAfter);

% ---- 4. clear selection at low mag ----
lb.clearLayer('selection', [], [], [1 1], [1 1], mf);
selNow = nnz(squeeze(lb.getData63('selection', 3, [], o)));
assert(selNow == 0, 'FAIL clear: %d selection px remain', selNow);
fprintf('4 clear at low mag: selection px=%d\n', selNow);

% ---- 5. bounded per-edit cost ----
lb.clearLayer('selection', [], [], [1 1], [1 1], mf);
o2 = struct('magFactor',64,'x',[1 W],'y',[1 H],'z',[1 1],'t',[1 1]);
d2 = uint8(zeros(round([H W]/64))); d2(50:120, 50:120) = 1;
t = tic; lb.setData63(d2, 'selection', 3, [], o2); dt = toc(t);
assert(dt < 0.2, 'FAIL stroke cost %.3f s', dt);
fprintf('5 bounded edit cost: 2%% stroke %.1f ms\n', dt*1000);

% ---- 6. Save materializes all levels ----
lb.materializeAll([]);
assert(all(lb.matLevel(lb.matLevel>0) == 1), 'FAIL Save: not all at level 1');
fprintf('6 Save materializeAll: all nonzero tiles at level 1\n');

% ---- 7. persistence + fallback ----
lb.closeStore();
assert(isfile([sp '.levelmap.mat']), 'FAIL side-file not written');
lb2 = core.MibBigDataLabels([], bm); lb2.openStore(sp);
assert(any(lb2.matLevel(:) > 0), 'FAIL matLevel not restored');
lb2.closeStore();
delete([sp '.levelmap.mat']);
lb3 = core.MibBigDataLabels([], bm); lb3.openStore(sp);   % must not error
assert(any(lb3.matLevel(:) > 0), 'FAIL fallback empty');
lb3.closeStore();
fprintf('7 persistence + fallback: OK\n');

if isfolder(sp); rmdir(sp, 's'); end
disp('ALL LEVELMAP CHECKS PASSED');
end
