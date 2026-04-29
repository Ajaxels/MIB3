function repositionDrawingROI(obj)
% REPOSITIONDRAWINGROI - Reposition the active interactive drawing tool after zoom/pan redraws.
%
% Syntax:
%   function repositionDrawingROI(obj)
%
% the image at a different axes coordinate scale.
%
% Called from controllers.MibController.showImage at the end of every
% image redraw, so it fires after both scroll-wheel zoom and pan.
%
% The stored data-pixel coordinates in obj.drawingROI.dataPos are
% converted back to current axes coordinates via
% models.MibModel.convertDataToMouseCoordinates and applied to the live
% drawing object, keeping the ROI visually anchored to the same image pixels.
%
% Input Arguments:
%   - **obj** — controllers.MibRoi
%
%   Return values: none
%

if ~obj.drawingROI.active; return; end

roi = obj.drawingROI.roi;
if isempty(roi) || ~isvalid(roi); return; end
if isempty(obj.drawingROI.dataPos); return; end
if obj.drawingROI.repositioning; return; end   % re-entry guard

obj.drawingROI.repositioning = true;
try
    dp = obj.drawingROI.dataPos;   % data-pixel coords, shape-dependent (see addROI)

    switch obj.drawingROI.type
        case 'Rectangle'
            % dp = [xmin ymin; xmax ymax]
            [Xax, Yax] = obj.mibModel.convertDataToMouseCoordinates(dp(:,1), dp(:,2), 'shown');
            w = Xax(2) - Xax(1);
            h = Yax(2) - Yax(1);
            if w > 0 && h > 0
                roi.Position = [Xax(1), Yax(1), w, h];
            end

        case 'Ellipse'
            % dp = [cx cy rx ry] – center and semi-axes in data pixels
            cx = dp(1);  cy = dp(2);
            rx = dp(3);  ry = dp(4);
            % convert center
            [cx_ax, cy_ax] = obj.mibModel.convertDataToMouseCoordinates(cx,    cy,    'shown');
            % convert an edge point on each axis to get the scaled semi-axis length
            [ex_ax, ~]     = obj.mibModel.convertDataToMouseCoordinates(cx+rx, cy,    'shown');
            [~,     ey_ax] = obj.mibModel.convertDataToMouseCoordinates(cx,    cy+ry, 'shown');
            rx_ax = abs(ex_ax - cx_ax);
            ry_ax = abs(ey_ax - cy_ax);
            if rx_ax > 0 && ry_ax > 0
                roi.Center   = [cx_ax, cy_ax];
                roi.SemiAxes = [rx_ax, ry_ax];
            end

        otherwise
            % Polygon / Freehand: dp = [N×2] vertices in data pixels
            [Xax, Yax] = obj.mibModel.convertDataToMouseCoordinates(dp(:,1), dp(:,2), 'shown');
            roi.Position = [Xax(:), Yax(:)];
    end
catch
end

obj.drawingROI.repositioning = false;
end
