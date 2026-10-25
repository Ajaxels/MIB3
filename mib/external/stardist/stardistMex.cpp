/*
 * STARDISTMEX - StarDist 2D polygon non-maximum suppression and ray distances, as a MEX function.
 *
 *   keep = stardistMex('nms', dist, points, nmsThresh, useKdtree, useBbox)
 *   dist = stardistMex('starDist', labelMap, nRays, gridRow, gridCol)
 *
 * 'nms'      - greedy suppression of polygon candidates sorted by descending score;
 *              dist [n, nRays] single, points [n, 2] single (0-based row, col),
 *              nmsThresh double, useKdtree/useBbox logical; keep [n, 1] logical.
 *              Candidate j is suppressed by an earlier kept candidate i when
 *              intersection / min(area_i, area_j) > nmsThresh.
 * 'starDist' - ray distances from every grid pixel (gridRow*i, gridCol*j) of a label map;
 *              labelMap [H, W] uint32, nRays, gridRow, gridCol double;
 *              dist [ceil(H/gridRow), ceil(W/gridCol), nRays] single.
 *
 * Called by deepmib.stardist.nms and deepmib.stardist.computeTargets, which document the
 * algorithms and fall back to MATLAB code when this MEX file is missing.
 *
 * Adapted from stardist/lib/stardist2d.cpp (c_non_max_suppression_inds, c_star_dist) of
 * StarDist 0.9.2, Copyright (c) 2018-2025, Uwe Schmidt, Martin Weigert, BSD 3-Clause License,
 * see stardist_license.txt. Uses Clipper 6.4.2 (Boost Software License, clipper_license.txt)
 * and nanoflann 1.3.2 (BSD License, nanoflann_license.txt) as bundled with StarDist.
 * Changes from the original: the Python/numpy C-API is replaced by the MATLAB MEX API; arrays
 * are column-major; label ids are uint32 instead of uint16; Ctrl+C is checked with
 * utIsInterruptPending. The geometry, the float arithmetic and the order of operations are
 * unchanged, so the results equal those of StarDist.
 *
 * Build: deployment/mib3_compile_c_files.m. StarDist's OpenMP pragmas are kept, but the MEX
 * file is built without OpenMP: single-threaded it is as fast as StarDist's own build, and
 * OpenMP would add a runtime DLL dependency.
 */
#include "mex.h"
#include <math.h>
#include <cmath>
#include <cstring>
#include <vector>

#include "clipper.hpp"
#include "nanoflann.hpp"

#ifdef _OPENMP
#include <omp.h>
#endif

#ifndef M_PI
#define M_PI 3.141592653589793
#endif

extern "C" bool utIsInterruptPending(void);

template <typename T>
struct PointCloud2D
{
    struct Point
    {
        T x, y;
    };
    std::vector<Point> pts;
    inline size_t kdtree_get_point_count() const { return pts.size(); }
    inline T kdtree_get_pt(const size_t idx, const size_t dim) const
    {
        if (dim == 0) return pts[idx].x;
        else return pts[idx].y;
    }
    template <class BBOX>
    bool kdtree_get_bbox(BBOX& /* bb */) const { return false; }
};

inline int round_to_int(float r) {
    return (int)lrint(r);
}

inline float area_from_path(ClipperLib::Path p) {
    float area = 0;
    const int n = p.size();
    for (int i = 0; i < n; i++) {
        area += p[i].X * p[(i+1)%n].Y -
                p[i].Y * p[(i+1)%n].X;
    }
    area = 0.5 * abs(area);
    return area;
}

// the arguments are int: StarDist passes float boxes, which are truncated here
inline bool bbox_intersect(const int bbox_a_x1, const int bbox_a_x2,
                           const int bbox_a_y1, const int bbox_a_y2,
                           const int bbox_b_x1, const int bbox_b_x2,
                           const int bbox_b_y1, const int bbox_b_y2) {
    return (bbox_b_x1 <= bbox_a_x2 && bbox_a_x1 <= bbox_b_x2 && bbox_b_y1 <= bbox_a_y2 && bbox_a_y1 <= bbox_b_y2);
}

inline float poly_intersection_area(const ClipperLib::Path poly_a_path, const ClipperLib::Path poly_b_path) {
    ClipperLib::Clipper c;
    ClipperLib::Paths res;
    c.Clear();
    c.AddPath(poly_a_path, ClipperLib::ptClip, true);
    c.AddPath(poly_b_path, ClipperLib::ptSubject, true);
    c.Execute(ClipperLib::ctIntersection, res, ClipperLib::pftNonZero, ClipperLib::pftNonZero);
    float area_inter = 0;
    for (unsigned int r = 0; r < res.size(); r++)
        area_inter += area_from_path(res[r]);
    return area_inter;
}

static void non_max_suppression(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
    if (nrhs != 6)
        mexErrMsgIdAndTxt("stardistMex:nms:nargin", "Usage: keep = stardistMex('nms', dist, points, nmsThresh, useKdtree, useBbox)");
    const mxArray *dist_arr = prhs[1];
    const mxArray *points_arr = prhs[2];
    if (!mxIsSingle(dist_arr) || !mxIsSingle(points_arr) || mxIsComplex(dist_arr) || mxIsComplex(points_arr))
        mexErrMsgIdAndTxt("stardistMex:nms:type", "dist and points must be real single arrays");
    const mwSize n_polys = mxGetM(dist_arr);
    const int n_rays = (int)mxGetN(dist_arr);
    if (mxGetM(points_arr) != n_polys || mxGetN(points_arr) != 2)
        mexErrMsgIdAndTxt("stardistMex:nms:size", "points must be [n, 2] for dist [n, nRays]");
    const float threshold = (float)mxGetScalar(prhs[3]);
    const int use_kdtree = mxGetScalar(prhs[4]) != 0;
    const int use_bbox = mxGetScalar(prhs[5]) != 0;

    const float *dist = (const float *)mxGetData(dist_arr);       // dist(i, k) = dist[i + k*n]
    const float *points_cm = (const float *)mxGetData(points_arr);
    // StarDist keeps points as interleaved (row, col) pairs; the kd-tree query needs them so
    std::vector<float> points(2 * n_polys);
    for (mwSize i = 0; i < n_polys; i++) {
        points[2*i] = points_cm[i];
        points[2*i+1] = points_cm[i + n_polys];
    }

    plhs[0] = mxCreateLogicalMatrix(n_polys, 1);
    mxLogical *keep = mxGetLogicals(plhs[0]);
    if (n_polys == 0) return;

    std::vector<float> bbox_x1(n_polys), bbox_x2(n_polys), bbox_y1(n_polys), bbox_y2(n_polys);
    std::vector<float> radius_outer(n_polys), areas(n_polys);
    std::vector<char> suppressed(n_polys, 0);
    std::vector<ClipperLib::Path> poly_paths(n_polys);
    const float ANGLE_PI = 2*M_PI/n_rays;

    // build polys and areas
    for (long i = 0; i < (long)n_polys; i++) {
        ClipperLib::Path clip;
        const float py = points[2*i];
        const float px = points[2*i+1];
        float max_radius_outer = 0;
        for (int k = 0; k < n_rays; k++) {
            const float d = dist[i + (mwSize)k * n_polys];
            const float y = (float)(py+d*sin(ANGLE_PI*k));
            const float x = (float)(px+d*cos(ANGLE_PI*k));
            if (k == 0) {
                bbox_x1[i] = x;
                bbox_x2[i] = x;
                bbox_y1[i] = y;
                bbox_y2[i] = y;
            } else {
                bbox_x1[i] = (x < bbox_x1[i]) ? x : bbox_x1[i];
                bbox_x2[i] = (x > bbox_x2[i]) ? x : bbox_x2[i];
                bbox_y1[i] = (y < bbox_y1[i]) ? y : bbox_y1[i];
                bbox_y2[i] = (y > bbox_y2[i]) ? y : bbox_y2[i];
            }
            clip << ClipperLib::IntPoint(x, y);
            max_radius_outer = fmax(d, max_radius_outer);
        }
        radius_outer[i] = max_radius_outer;
        poly_paths[i] = clip;
        areas[i] = area_from_path(clip);
    }

    // build kdtree
    PointCloud2D<float> cloud;
    nanoflann::SearchParams params;
    std::vector<std::pair<size_t, float>> results;
    float max_dist = 0;
    cloud.pts.resize(n_polys);
    for (long i = 0; i < (long)n_polys; i++) {
        cloud.pts[i].x = points[2*i];
        cloud.pts[i].y = points[2*i+1];
        max_dist = (radius_outer[i] > max_dist) ? radius_outer[i] : max_dist;
    }
    typedef nanoflann::KDTreeSingleIndexAdaptor<
        nanoflann::L2_Simple_Adaptor<float, PointCloud2D<float>>,
        PointCloud2D<float>, 2> my_kd_tree_t;
    my_kd_tree_t index(2, cloud, nanoflann::KDTreeSingleIndexAdaptorParams(10 /* max leaf */));
    if (use_kdtree)
        index.buildIndex();

    // suppress (double loop)
    for (long i = 0; i < (long)n_polys - 1; i++) {
        if (suppressed[i]) continue;
        if (utIsInterruptPending())
            mexErrMsgIdAndTxt("stardistMex:interrupted", "StarDist NMS interrupted");

        if (use_kdtree)
            index.radiusSearch(&points[2*i],
                               (max_dist+radius_outer[i])*(max_dist+radius_outer[i]),
                               results, params);
        else {
            results.resize(n_polys - i);
            for (size_t n = 0; n < results.size(); ++n)
                results[n].first = i + n;
        }

#pragma omp parallel for schedule(dynamic) shared(suppressed)
        for (long neigh = 0; neigh < (long)results.size(); neigh++) {
            long j = results[neigh].first;
            if ((suppressed[j]) || (j <= i))
                continue;
            if ((use_bbox) && (!bbox_intersect(bbox_x1[i], bbox_x2[i], bbox_y1[i], bbox_y2[i], bbox_x1[j], bbox_x2[j], bbox_y1[j], bbox_y2[j])))
                continue;
            const float area_inter = poly_intersection_area(poly_paths[i], poly_paths[j]);
            const float overlap = area_inter / fmin(areas[i]+1.e-10, areas[j]+1.e-10);
            if (overlap > threshold)
                suppressed[j] = 1;
        }
    }

    for (mwSize i = 0; i < n_polys; i++)
        keep[i] = !suppressed[i];
}

static void star_dist(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
    if (nrhs != 5)
        mexErrMsgIdAndTxt("stardistMex:starDist:nargin", "Usage: dist = stardistMex('starDist', labelMap, nRays, gridRow, gridCol)");
    const mxArray *src_arr = prhs[1];
    if (!mxIsUint32(src_arr) || mxGetNumberOfDimensions(src_arr) != 2)
        mexErrMsgIdAndTxt("stardistMex:starDist:type", "labelMap must be a 2D uint32 array");
    const int n_rays = (int)mxGetScalar(prhs[2]);
    const int grid_y = (int)mxGetScalar(prhs[3]);
    const int grid_x = (int)mxGetScalar(prhs[4]);
    if (n_rays < 3 || grid_y < 1 || grid_x < 1)
        mexErrMsgIdAndTxt("stardistMex:starDist:value", "nRays must be >= 3 and the grid >= 1");

    const long dims0 = (long)mxGetM(src_arr);      // rows
    const long dims1 = (long)mxGetN(src_arr);      // columns
    const unsigned int *src = (const unsigned int *)mxGetData(src_arr);   // src(i, j) = src[i + j*rows]

    mwSize dims_dst[3];
    dims_dst[0] = (dims0 - 1) / grid_y + 1;
    dims_dst[1] = (dims1 - 1) / grid_x + 1;
    dims_dst[2] = n_rays;
    plhs[0] = mxCreateNumericArray(3, dims_dst, mxSINGLE_CLASS, mxREAL);
    float *dst = (float *)mxGetData(plhs[0]);       // dst(i, j, k) = dst[i + j*h + k*h*w]
    const long h = (long)dims_dst[0];
    const long w = (long)dims_dst[1];

#pragma omp parallel for schedule(dynamic)
    for (long i = 0; i < h; i++) {
        for (long j = 0; j < w; j++) {
            const unsigned int value = src[i*grid_y + (j*grid_x)*dims0];
            if (value == 0) {
                for (int k = 0; k < n_rays; k++)
                    dst[i + j*h + k*h*w] = 0;
            } else {
                const float st_rays = (2*M_PI) / n_rays;
                for (int k = 0; k < n_rays; k++) {
                    const float phi = k*st_rays;
                    const float dy = cos(phi);
                    const float dx = sin(phi);
                    float x = 0, y = 0;
                    while (1) {
                        x += dx;
                        y += dy;
                        const int ii = round_to_int(i*grid_y+x), jj = round_to_int(j*grid_x+y);
                        if (ii < 0 || ii >= dims0 ||
                            jj < 0 || jj >= dims1 ||
                            value != src[ii + (long)jj*dims0]) {
                            const float t_corr = .5f/fmax(fabs(dx), fabs(dy));
                            x += (t_corr-1.f)*dx;
                            y += (t_corr-1.f)*dy;
                            const float dist = sqrt(x*x + y*y);
                            dst[i + j*h + k*h*w] = dist;
                            break;
                        }
                    }
                }
            }
        }
    }
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
    if (nrhs < 1 || !mxIsChar(prhs[0]))
        mexErrMsgIdAndTxt("stardistMex:command", "First argument must be 'nms' or 'starDist'");
    char command[16];
    mxGetString(prhs[0], command, sizeof(command));
    if (strcmp(command, "nms") == 0)
        non_max_suppression(nlhs, plhs, nrhs, prhs);
    else if (strcmp(command, "starDist") == 0)
        star_dist(nlhs, plhs, nrhs, prhs);
    else
        mexErrMsgIdAndTxt("stardistMex:command", "Unknown command '%s'; use 'nms' or 'starDist'", command);
}
